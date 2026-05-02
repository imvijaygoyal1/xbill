//
//  KeychainSessionStorage.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
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
        try? keychain.data(forKey: "auth_\(key)")
    }

    func remove(key: String) throws {
        try? keychain.delete(forKey: "auth_\(key)")
    }
}
