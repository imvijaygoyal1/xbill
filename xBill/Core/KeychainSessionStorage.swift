//
//  KeychainSessionStorage.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import Security
import Supabase

// MARK: - KeychainSessionStorage
//
// Replaces the Supabase SDK's default KeychainLocalStorage, which uses
// kSecAttrAccessibleAfterFirstUnlock (backup-eligible). This implementation
// uses kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly so session tokens:
//   • are never included in iCloud or iTunes/Finder backups
//   • cannot be migrated to another device
//   • remain accessible to background token refresh after first unlock

final class KeychainSessionStorage: AuthLocalStorage, @unchecked Sendable {
    private let keychain = KeychainManager.shared

    func store(key: String, value: Data) throws {
        try keychain.save(value, forKey: "auth_\(key)")
    }

    func retrieve(key: String) throws -> Data? {
        // M-29: use the raw Security API so we can distinguish errSecInteractionNotAllowed
        // (Keychain locked after reboot, not yet unlocked) from errSecItemNotFound ("no session").
        // Treating the former as nil would cause the Supabase SDK to force sign-out unnecessarily.
        let query: [CFString: Any] = [
            kSecClass:           kSecClassGenericPassword,
            kSecAttrService:     "com.xbill.app",
            kSecAttrAccount:     "auth_\(key)",
            kSecReturnData:      true,
            kSecMatchLimit:      kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            // No session stored — normal on fresh install or after sign-out.
            return nil
        case errSecInteractionNotAllowed:
            // Keychain is locked (device rebooted, not yet unlocked for the first time).
            // Throw so the SDK treats this as a transient error, not a missing session.
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(errSecInteractionNotAllowed),
                userInfo: [NSLocalizedDescriptionKey: "Keychain locked — please unlock your device."]
            )
        default:
            // Any other Keychain error: surface it so it can be logged/retried rather
            // than silently treated as "no session".
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Keychain retrieve failed with status \(status)."]
            )
        }
    }

    func remove(key: String) throws {
        try? keychain.delete(forKey: "auth_\(key)")
    }
}
