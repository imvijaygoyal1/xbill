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
    // M-19: must not be nonisolated — called from the @MainActor init(), and the body
    // calls KeychainManager.shared.save() which is not concurrency-safe from an arbitrary thread.
    @MainActor private func migrateFromUserDefaultsIfNeeded() {
        let ud = UserDefaults.standard
        guard ud.object(forKey: "appLockEnabled") != nil else { return }
        let wasEnabled = ud.bool(forKey: "appLockEnabled")
        try? KeychainManager.shared.save(wasEnabled ? "true" : "false",
                                         forKey: KeychainManager.Keys.appLockEnabled)
        ud.removeObject(forKey: "appLockEnabled")
    }

    // MARK: - Biometry (cached at init to avoid repeated LAContext creation)

    private(set) var cachedBiometryType: LABiometryType = {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        return ctx.biometryType
    }()

    var biometryType: LABiometryType { cachedBiometryType }

    var lockIconName: String {
        switch cachedBiometryType {
        case .faceID:   return "faceid"
        case .touchID:  return "touchid"
        default:        return "lock.fill"
        }
    }

    var unlockLabel: String {
        switch cachedBiometryType {
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
            if let err = error, err.code == LAError.passcodeNotSet.rawValue {
                // Device has no passcode — App Lock cannot function; disable permanently.
                isEnabled = false
                isLocked = false
            }
            // For other transient errors (enclave unavailable on reboot, etc.) stay locked.
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
