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

    private let service = ActivityService.shared
    private let auth    = AuthService.shared
    private let store   = NotificationStore.shared

    private var currentUserID: UUID? { auth.currentUserID }
    private var readMutationGeneration: [UUID: Int] = [:]
    private var readMutationTasks: [UUID: Task<Void, Never>] = [:]

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            guard let userID = auth.currentUserID else { throw AppError.unauthenticated }
            // Read unreadCount before the fetch/merge so the badge reflects the
            // pre-fetch state and isn't overwritten by a concurrent markRead call.
            let fetchedItems = try await service.fetchRecentActivity(userID: userID)
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
        if let userID = auth.currentUserID {
            for item in items { store.setPendingReadState(id: item.id, isRead: true, userID: userID) }
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
        let previous = item
        let previousItems = items
        store.markRead(id: item.id, userID: currentUserID)
        replace(item.id) { $0.isRead = true }
        refreshUnreadCount()
        guard let userID = currentUserID else {
            NotificationService.shared.setBadge(unreadCount)
            return
        }
        store.setPendingReadState(id: item.id, isRead: true, userID: userID)
        let generation = nextReadMutationGeneration(for: item.id)
        let previousTask = readMutationTasks[item.id]
        let task = Task { @MainActor in
            await previousTask?.value
            guard readMutationGeneration[item.id] == generation else { return }
            guard await service.markRead(id: item.id) else {
                guard readMutationGeneration[item.id] == generation else { return }
                store.clearPendingReadState(id: item.id, userID: userID)
                store.replaceWithRemote(previousItems, userID: userID)
                replace(item.id) { $0 = previous }
                refreshUnreadCount()
                NotificationService.shared.setBadge(unreadCount)
                errorAlert = ErrorAlert(title: "Activity Update Failed", message: "This notification could not be marked read. Try again.")
                return
            }
            guard readMutationGeneration[item.id] == generation else { return }
            store.clearPendingReadState(id: item.id, userID: userID)
            readMutationTasks.removeValue(forKey: item.id)
        }
        readMutationTasks[item.id] = task
        NotificationService.shared.setBadge(unreadCount)
    }

    func markUnread(_ item: NotificationItem) {
        let previous = item
        let previousItems = items
        store.markUnread(id: item.id, userID: currentUserID)
        replace(item.id) { $0.isRead = false }
        refreshUnreadCount()
        guard let userID = currentUserID else {
            NotificationService.shared.setBadge(unreadCount)
            return
        }
        store.setPendingReadState(id: item.id, isRead: false, userID: userID)
        let generation = nextReadMutationGeneration(for: item.id)
        let previousTask = readMutationTasks[item.id]
        let task = Task { @MainActor in
            await previousTask?.value
            guard readMutationGeneration[item.id] == generation else { return }
            guard await service.markUnread(id: item.id) else {
                guard readMutationGeneration[item.id] == generation else { return }
                store.clearPendingReadState(id: item.id, userID: userID)
                store.replaceWithRemote(previousItems, userID: userID)
                replace(item.id) { $0 = previous }
                refreshUnreadCount()
                NotificationService.shared.setBadge(unreadCount)
                errorAlert = ErrorAlert(title: "Activity Update Failed", message: "This notification could not be marked unread. Try again.")
                return
            }
            guard readMutationGeneration[item.id] == generation else { return }
            store.clearPendingReadState(id: item.id, userID: userID)
            readMutationTasks.removeValue(forKey: item.id)
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
