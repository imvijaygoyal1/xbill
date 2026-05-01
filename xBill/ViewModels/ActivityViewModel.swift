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
            items = try await service.fetchRecentActivity(userID: userID)
            unreadCount = store.unreadCount()
        } catch {
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }

    func markAllRead() {
        store.markAllRead()
        unreadCount = 0
    }

    var hasUnread: Bool { unreadCount > 0 }
}
