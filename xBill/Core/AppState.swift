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
}
