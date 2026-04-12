import SwiftUI
import UIKit

// MARK: - AppDelegate (handles APNs device token)

class AppDelegate: NSObject, UIApplicationDelegate {
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
}

// MARK: - App

@main
struct xBillApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var authVM = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(authVM: authVM)
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
                .tint(Color.brandPrimary)
        }
    }
}
