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
    private init() {}

    var isLocked: Bool = false

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "appLockEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "appLockEnabled") }
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
