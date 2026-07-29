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
    /// What the app icon badge should show. Only `public.notifications` rows count, because
    /// APNs overwrites the icon badge with a server-side count of exactly those rows.
    /// `unreadCount` drives the in-app tab badge and also includes local history rows.
    var iconBadgeCount: Int = 0

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
    private var deleteTasks: [UUID: Task<Void, Never>] = [:]
    private var markAllReadTask: Task<Void, Never>?

    /// Whether any read-state, mark-all or delete write is still settling. Derived from the
    /// in-flight task state.
    var hasInFlightMutations: Bool {
        !readMutationTasks.isEmpty || !deleteTasks.isEmpty || markAllReadTask != nil
    }

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
            iconBadgeCount = store.serverUnreadCount(userID: userID)
            NotificationService.shared.setBadge(iconBadgeCount)
        } catch {
            // On partial failure, ActivityService still merges results into the store.
            // Read from the store so previously fetched items remain visible.
            let storedItems = store.loadAll(userID: currentUserID)
            if !storedItems.isEmpty {
                items       = storedItems
                unreadCount = store.unreadCount(userID: currentUserID)
                iconBadgeCount = store.serverUnreadCount(userID: currentUserID)
                NotificationService.shared.setBadge(iconBadgeCount)
            }
            // Unauthenticated errors are expected on session expiry — don't show alert.
            guard !AppError.isSilent(error) else { return }
            if case AppError.unauthenticated = AppError.from(error) { return }
            self.errorAlert = ErrorAlert(title: "Some activity could not be loaded", message: error.localizedDescription)
        }
    }

    func markAllRead() {
        let previousItems = items
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
            markAllReadTask = Task { @MainActor in
                defer { markAllReadTask = nil }
                guard await service.markAllRead(userID: userID) else {
                    store.clearPendingReadStates(userID: userID)
                    // Revert only the rows the failed call was responsible for. A history
                    // row's read state is local-only — its write succeeded and must not be
                    // undone by an unrelated server failure.
                    let previousReadState = Dictionary(
                        previousItems.map { ($0.id, $0.isRead) },
                        uniquingKeysWith: { _, new in new }
                    )
                    for index in items.indices where items[index].isServerBacked {
                        guard let wasRead = previousReadState[items[index].id] else { continue }
                        items[index].isRead = wasRead
                        if wasRead {
                            store.markRead(id: items[index].id, userID: userID)
                        } else {
                            store.markUnread(id: items[index].id, userID: userID)
                        }
                    }
                    refreshUnreadCount()
                    NotificationService.shared.setBadge(iconBadgeCount)
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
            NotificationService.shared.setBadge(iconBadgeCount)
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
            // Logged on success as well as failure: without this a device log can only show
            // the absence of errors, never which row kind was actually exercised.
            AppDiagnostics.log(.balance, "ActivityViewModel.readState.remote", [
                ("id", item.id.uuidString),
                ("isRead", "\(isRead)"),
                ("succeeded", "\(succeeded)")
            ])
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
                NotificationService.shared.setBadge(iconBadgeCount)
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
        NotificationService.shared.setBadge(iconBadgeCount)
    }

    func delete(_ item: NotificationItem) {
        let originalIndex = items.firstIndex { $0.id == item.id }
        store.delete(id: item.id, userID: currentUserID)
        items.removeAll { $0.id == item.id }
        refreshUnreadCount()

        guard let userID = currentUserID else {
            NotificationService.shared.setBadge(iconBadgeCount)
            return
        }

        // A history row has no server row to delete. Record the dismissal so the next fetch
        // does not re-derive it straight back out of the expense list.
        guard item.isServerBacked else {
            store.dismissHistoryItem(id: item.id, userID: userID)
            AppDiagnostics.log(.balance, "ActivityViewModel.delete.localOnly", [
                ("id", item.id.uuidString)
            ])
            NotificationService.shared.setBadge(iconBadgeCount)
            return
        }

        let task = Task { @MainActor in
            defer { deleteTasks.removeValue(forKey: item.id) }
            guard await service.delete(id: item.id) else {
                // Restore just this row, at the position it was removed from. Reinstating a
                // whole snapshot of `items` would also revert rows changed meanwhile.
                let index = min(originalIndex ?? items.count, items.count)
                items.insert(item, at: index)
                store.mergeRemote([item], userID: userID)
                refreshUnreadCount()
                NotificationService.shared.setBadge(iconBadgeCount)
                errorAlert = ErrorAlert(title: "Activity Update Failed", message: "This notification could not be deleted. Try again.")
                return
            }
        }
        deleteTasks[item.id] = task
        NotificationService.shared.setBadge(iconBadgeCount)
    }

    func refreshUnreadCount() {
        unreadCount = store.unreadCount(userID: currentUserID)
        iconBadgeCount = store.serverUnreadCount(userID: currentUserID)
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
