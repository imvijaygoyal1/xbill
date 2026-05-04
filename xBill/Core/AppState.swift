//
//  AppState.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import Observation

// MARK: - AppState

/// Singleton observable that bridges UIKit (AppDelegate, NSUserActivity) with SwiftUI views.
/// Stores pending navigation intents set from outside the SwiftUI hierarchy.
@Observable
final class AppState: @unchecked Sendable {
    static let shared = AppState()
    private init() {}

    // MARK: - Quick Actions

    enum QuickAction: Equatable, Sendable {
        case addExpense
        case scanReceipt
    }

    var pendingQuickAction: QuickAction?

    // MARK: - Spotlight Navigation

    enum SpotlightTarget: Equatable, Sendable {
        case group(UUID)
    }

    var spotlightTarget: SpotlightTarget?

    // MARK: - Push Notification Navigation

    enum NotificationTarget: Equatable, Sendable {
        case group(UUID)
    }

    var pendingNotificationTarget: NotificationTarget?

    // MARK: - Add Friend via QR / Deep Link

    /// Set when the app is opened via xbill://add/<userID>. MainTabView resolves this.
    var pendingAddFriendUserID: UUID?
}
