//
//  KeychainManager.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import Security
import CryptoKit

// MARK: - KeychainManager

final class KeychainManager: Sendable {
    static let shared = KeychainManager()
    private init() {}

    private let service = "com.xbill.app"

    // MARK: Save

    func save(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw AppError.validationFailed("Cannot encode value for key: \(key)")
        }
        try save(data, forKey: key)
    }

    func save(_ data: Data, forKey key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData] = data
        // ThisDeviceOnly: excludes item from backups and prevents migration to another device.
        attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AppError.unknown("Keychain save failed: \(status)")
        }
    }

    // MARK: Read

    func string(forKey key: String) throws -> String {
        let data = try data(forKey: key)
        guard let string = String(data: data, encoding: .utf8) else {
            throw AppError.decodingFailed("Cannot decode string for key: \(key)")
        }
        return string
    }

    func data(forKey key: String) throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            throw AppError.notFound
        }
        return data
    }

    // MARK: Delete

    func delete(forKey key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.unknown("Keychain delete failed: \(status)")
        }
    }
}

// MARK: - Keys

extension KeychainManager {
    enum Keys {
        static let sessionToken      = "session_token"
        static let refreshToken      = "refresh_token"
        static let cacheEncryptionKey = "cache_encryption_key"
    }

    /// Returns the AES-256 key used to encrypt UserDefaults cache entries.
    /// Generates and persists a new key on first call.
    func cacheEncryptionKey() throws -> SymmetricKey {
        if let data = try? data(forKey: Keys.cacheEncryptionKey) {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        try save(keyData, forKey: Keys.cacheEncryptionKey)
        return key
    }
}
