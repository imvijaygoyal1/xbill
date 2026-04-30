//
//  xBillApp.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI
import UIKit
import CoreSpotlight

// MARK: - AppDelegate (handles APNs device token + quick actions)

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        registerShortcutItems()

        // Handle cold-launch from a shortcut (return false so performActionFor is NOT called again)
        if let shortcutItem = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            if let action = quickAction(for: shortcutItem.type) {
                AppState.shared.pendingQuickAction = action
            }
            return false
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { try? await AuthService.shared.updateDeviceToken(tokenString) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Non-critical — push notifications degrade gracefully
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        if let action = quickAction(for: shortcutItem.type) {
            AppState.shared.pendingQuickAction = action
            completionHandler(true)
        } else {
            completionHandler(false)
        }
    }

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        guard userActivity.activityType == CSSearchableItemActionType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String
        else { return false }

        let parts = identifier.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let uuidString = parts.last.map(String.init),
              let uuid = UUID(uuidString: uuidString)
        else { return false }

        if parts.first == "group" {
            AppState.shared.spotlightTarget = .group(uuid)
            return true
        }
        return false
    }

    // MARK: - Helpers

    private func registerShortcutItems() {
        UIApplication.shared.shortcutItems = [
            UIApplicationShortcutItem(
                type: "com.vijaygoyal.xbill.addExpense",
                localizedTitle: "Add Expense",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "plus.circle")
            ),
            UIApplicationShortcutItem(
                type: "com.vijaygoyal.xbill.scanReceipt",
                localizedTitle: "Scan Receipt",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "doc.text.viewfinder")
            )
        ]
    }

    private func quickAction(for type: String) -> AppState.QuickAction? {
        switch type {
        case "com.vijaygoyal.xbill.addExpense":  return .addExpense
        case "com.vijaygoyal.xbill.scanReceipt": return .scanReceipt
        default: return nil
        }
    }
}

// MARK: - App

@main
struct xBillApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var authVM = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(authVM: authVM)
                .environment(AppState.shared)
                .task { await authVM.loadCurrentUser() }
                .task { await authVM.startListeningToAuthChanges() }
                .onOpenURL { url in
                    if url.scheme == "xbill", url.host == "join" {
                        let token = url.lastPathComponent
                        if !token.isEmpty {
                            authVM.pendingJoinRequest = InviteJoinRequest(token: token)
                        }
                    } else {
                        Task {
                            try? await SupabaseManager.shared.auth.session(from: url)
                        }
                    }
                }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
                    let parts = identifier.split(separator: ":", maxSplits: 1)
                    guard parts.count == 2, let uuidString = parts.last, let uuid = UUID(uuidString: String(uuidString)) else { return }
                    if parts.first == "group" {
                        AppState.shared.spotlightTarget = .group(uuid)
                    }
                }
                .tint(Color.brandPrimary)
        }
    }
}
