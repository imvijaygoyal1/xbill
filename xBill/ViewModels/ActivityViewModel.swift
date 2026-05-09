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

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            guard let userID = await auth.currentUserID else { throw AppError.unauthenticated }
            // Read unreadCount before the fetch/merge so the badge reflects the
            // pre-fetch state and isn't overwritten by a concurrent markRead call.
            let fetchedItems = try await service.fetchRecentActivity(userID: userID)
            items       = fetchedItems
            unreadCount = store.unreadCount()
        } catch {
            // On partial failure, ActivityService still merges results into the store.
            // Read from the store so previously fetched items remain visible.
            let storedItems = store.loadAll()
            if !storedItems.isEmpty {
                items       = storedItems
                unreadCount = store.unreadCount()
            }
            // Unauthenticated errors are expected on session expiry — don't show alert.
            guard !AppError.isSilent(error) else { return }
            if case AppError.unauthenticated = AppError.from(error) { return }
            self.errorAlert = ErrorAlert(title: "Some activity could not be loaded", message: error.localizedDescription)
        }
    }

    func markAllRead() {
        store.markAllRead()
        // Read back from the store rather than hardcoding 0 so that a silent
        // store failure doesn't permanently suppress the badge.
        unreadCount = store.unreadCount()
    }

    func markRead(_ item: NotificationItem) {
        store.markRead(id: item.id)
        replace(item.id) { $0.isRead = true }
        refreshUnreadCount()
    }

    func markUnread(_ item: NotificationItem) {
        store.markUnread(id: item.id)
        replace(item.id) { $0.isRead = false }
        refreshUnreadCount()
    }

    func delete(_ item: NotificationItem) {
        store.delete(id: item.id)
        items.removeAll { $0.id == item.id }
        refreshUnreadCount()
    }

    func refreshUnreadCount() {
        unreadCount = store.unreadCount()
    }

    var hasUnread: Bool { unreadCount > 0 }

    private func replace(_ id: UUID, mutate: (inout NotificationItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[index])
    }
}
