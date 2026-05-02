//
//  AppLockService.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import LocalAuthentication
import Observation

@Observable
@MainActor
final class AppLockService {
    static let shared = AppLockService()
    private init() { migrateFromUserDefaultsIfNeeded() }

    var isLocked: Bool = false

    // L1 fix: store in Keychain (device-bound, backup-excluded) rather than UserDefaults.
    // A backup restore to a different device won't carry this flag.
    var isEnabled: Bool {
        get {
            (try? KeychainManager.shared.string(forKey: KeychainManager.Keys.appLockEnabled)) == "true"
        }
        set {
            try? KeychainManager.shared.save(newValue ? "true" : "false",
                                             forKey: KeychainManager.Keys.appLockEnabled)
        }
    }

    // One-time migration: read old UserDefaults flag, persist to Keychain, then clear.
    private nonisolated func migrateFromUserDefaultsIfNeeded() {
        let ud = UserDefaults.standard
        guard ud.object(forKey: "appLockEnabled") != nil else { return }
        let wasEnabled = ud.bool(forKey: "appLockEnabled")
        try? KeychainManager.shared.save(wasEnabled ? "true" : "false",
                                         forKey: KeychainManager.Keys.appLockEnabled)
        ud.removeObject(forKey: "appLockEnabled")
    }

    // MARK: - Biometry

    var biometryType: LABiometryType {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        return ctx.biometryType
    }

    var lockIconName: String {
        switch biometryType {
        case .faceID:   return "faceid"
        case .touchID:  return "touchid"
        default:        return "lock.fill"
        }
    }

    var unlockLabel: String {
        switch biometryType {
        case .faceID:  return "Unlock with Face ID"
        case .touchID: return "Unlock with Touch ID"
        default:       return "Enter Passcode"
        }
    }

    // MARK: - Actions

    func lock() {
        guard isEnabled else { return }
        isLocked = true
    }

    func authenticate() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // Device has no passcode — App Lock cannot function; disable it automatically
            // so users are not permanently locked out of the app.
            isEnabled = false
            isLocked = false
            return
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock xBill to view your expenses."
            )
            if success { isLocked = false }
        } catch {
            // stays locked — user can retry via button
        }
    }
}
