//
//  ActivityViewModel.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import Observation

@Observable
@MainActor
final class ActivityViewModel {
    var items: [NotificationItem] = []
    var isLoading: Bool = false
    var errorAlert: ErrorAlert?
    var unreadCount: Int = 0

    private let service: ActivityReadWriting
    private let store: NotificationStore
    private let currentUserIDProvider: @MainActor () -> UUID?

    init(
        service: ActivityReadWriting = ActivityService.shared,
        store: NotificationStore = .shared,
        currentUserIDProvider: @escaping @MainActor () -> UUID? = { AuthService.shared.currentUserID }
    ) {
        self.service = service
        self.store = store
        self.currentUserIDProvider = currentUserIDProvider
    }

    private var currentUserID: UUID? { currentUserIDProvider() }
    private var readMutationGeneration: [UUID: Int] = [:]
    private var readMutationTasks: [UUID: Task<Void, Never>] = [:]

    /// Whether any read-state write is still settling. Derived from the in-flight task map.
    var hasInFlightReadMutations: Bool { !readMutationTasks.isEmpty }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            guard let userID = currentUserID else { throw AppError.unauthenticated }
            // Read unreadCount before the fetch/merge so the badge reflects the
            // pre-fetch state and isn't overwritten by a concurrent markRead call.
            let fetchedItems = try await service.fetchRecentActivity(userID: userID, limit: 50)
            await service.reconcilePendingReadStates(userID: userID)
            let storedItems = store.loadAll(userID: userID)
            items       = storedItems.isEmpty ? fetchedItems : storedItems
            unreadCount = store.unreadCount(userID: userID)
            NotificationService.shared.setBadge(unreadCount)
        } catch {
            // On partial failure, ActivityService still merges results into the store.
            // Read from the store so previously fetched items remain visible.
            let storedItems = store.loadAll(userID: currentUserID)
            if !storedItems.isEmpty {
                items       = storedItems
                unreadCount = store.unreadCount(userID: currentUserID)
                NotificationService.shared.setBadge(unreadCount)
            }
            // Unauthenticated errors are expected on session expiry — don't show alert.
            guard !AppError.isSilent(error) else { return }
            if case AppError.unauthenticated = AppError.from(error) { return }
            self.errorAlert = ErrorAlert(title: "Some activity could not be loaded", message: error.localizedDescription)
        }
    }

    func markAllRead() {
        let previousItems = items
        let previousUnreadCount = unreadCount
        store.markAllRead(userID: currentUserID)
        // Update the in-memory array so individual rows reflect read state
        // immediately without waiting for a reload from the store.
        items = items.map { var i = $0; i.isRead = true; return i }
        // Read back from the store rather than hardcoding 0 so that a silent
        // store failure doesn't permanently suppress the badge.
        unreadCount = store.unreadCount(userID: currentUserID)
        if let userID = currentUserID {
            // Only server-backed rows have a write to replay; a history row's read state
            // lives solely in the local store.
            for item in items where item.isServerBacked {
                store.setPendingReadState(id: item.id, isRead: true, userID: userID)
            }
            Task { @MainActor in
                guard await service.markAllRead(userID: userID) else {
                    store.clearPendingReadStates(userID: userID)
                    items = previousItems
                    unreadCount = previousUnreadCount
                    store.replaceWithRemote(previousItems, userID: userID)
                    NotificationService.shared.setBadge(unreadCount)
                    errorAlert = ErrorAlert(title: "Activity Update Failed", message: "Your notifications could not be marked read. Try again.")
                    return
                }
                store.clearPendingReadStates(userID: userID)
            }
        }
        NotificationService.shared.setBadge(0)
    }

    func markRead(_ item: NotificationItem) {
        setReadState(item, isRead: true)
    }

    func markUnread(_ item: NotificationItem) {
        setReadState(item, isRead: false)
    }

    /// Applies the new read state locally, then writes it through **only** for rows that
    /// exist in `public.notifications`.
    ///
    /// The Activity list also contains historical expense-derived rows whose id is an
    /// expense id. A PATCH for one of those matches zero rows on the server, so it is kept
    /// local-only: no request, no pending intent to replay, no failure alert. Its state
    /// survives a refresh because `ActivityReconciler` preserves the stored value.
    private func setReadState(_ item: NotificationItem, isRead: Bool) {
        let previousIsRead = item.isRead
        if isRead {
            store.markRead(id: item.id, userID: currentUserID)
        } else {
            store.markUnread(id: item.id, userID: currentUserID)
        }
        replace(item.id) { $0.isRead = isRead }
        refreshUnreadCount()

        guard let userID = currentUserID, item.isServerBacked else {
            AppDiagnostics.log(.balance, "ActivityViewModel.readState.localOnly", [
                ("id", item.id.uuidString),
                ("isRead", "\(isRead)"),
                ("serverBacked", "\(item.isServerBacked)")
            ])
            NotificationService.shared.setBadge(unreadCount)
            return
        }

        store.setPendingReadState(id: item.id, isRead: isRead, userID: userID)
        // The generation counter makes the newest toggle authoritative: a superseded
        // mutation neither issues its request nor applies its rollback.
        let generation = nextReadMutationGeneration(for: item.id)
        let previousTask = readMutationTasks[item.id]
        let task = Task { @MainActor in
            await previousTask?.value
            guard readMutationGeneration[item.id] == generation else { return }
            let succeeded = isRead
                ? await service.markRead(id: item.id)
                : await service.markUnread(id: item.id)
            guard readMutationGeneration[item.id] == generation else { return }
            defer { readMutationTasks.removeValue(forKey: item.id) }
            store.clearPendingReadState(id: item.id, userID: userID)
            guard succeeded else {
                // Roll back this row only. Restoring a whole snapshot of `items` here
                // would also revert unrelated rows changed while the write was in flight.
                if previousIsRead {
                    store.markRead(id: item.id, userID: userID)
                } else {
                    store.markUnread(id: item.id, userID: userID)
                }
                replace(item.id) { $0.isRead = previousIsRead }
                refreshUnreadCount()
                NotificationService.shared.setBadge(unreadCount)
                errorAlert = ErrorAlert(
                    title: "Activity Update Failed",
                    message: isRead
                        ? "This notification could not be marked read. Try again."
                        : "This notification could not be marked unread. Try again."
                )
                return
            }
        }
        readMutationTasks[item.id] = task
        NotificationService.shared.setBadge(unreadCount)
    }

    func delete(_ item: NotificationItem) {
        let previousItems = items
        store.delete(id: item.id, userID: currentUserID)
        items.removeAll { $0.id == item.id }
        refreshUnreadCount()
        guard let userID = currentUserID else {
            NotificationService.shared.setBadge(unreadCount)
            return
        }
        Task { @MainActor in
            guard await service.delete(id: item.id) else {
                items = previousItems
                store.replaceWithRemote(previousItems, userID: userID)
                refreshUnreadCount()
                NotificationService.shared.setBadge(unreadCount)
                errorAlert = ErrorAlert(title: "Activity Update Failed", message: "This notification could not be deleted. Try again.")
                return
            }
        }
        NotificationService.shared.setBadge(unreadCount)
    }

    func refreshUnreadCount() {
        unreadCount = store.unreadCount(userID: currentUserID)
    }

    var hasUnread: Bool { unreadCount > 0 }

    private func replace(_ id: UUID, mutate: (inout NotificationItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[index])
    }

    private func nextReadMutationGeneration(for id: UUID) -> Int {
        let next = (readMutationGeneration[id] ?? 0) + 1
        readMutationGeneration[id] = next
        return next
    }
}
