//
//  CacheService.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import CryptoKit

// MARK: - CacheService
// Persists groups, expenses, and members to UserDefaults for offline reading.
// Dates encoded as secondsSince1970 to avoid ISO8601 fractional-second edge cases.

// MARK: - Cached balance keys (for Widget access)
extension CacheService {
    static let netBalanceKey       = "xbill_net_balance"
    static let totalOwedKey        = "xbill_total_owed"
    static let totalOwingKey       = "xbill_total_owing"
    static let balanceCurrencyKey  = "xbill_balance_currency"
    static let balanceAvailableKey = "xbill_balance_available"
}

final class CacheService: Sendable {
    static let shared = CacheService()
    private init() {}

    // Prefer shared App Group suite so widgets can read cached data.
    // Falls back to UserDefaults.standard when the group isn't registered yet.
    // nonisolated(unsafe) is correct here: UserDefaults is thread-safe at runtime.
    nonisolated(unsafe) static let defaults: UserDefaults = UserDefaults(suiteName: "group.com.vijaygoyal.xbill") ?? .standard

    // MARK: - Groups

    func saveGroups(_ groups: [BillGroup]) {
        save(groups, key: "xbill_groups")
    }

    func loadGroups() -> [BillGroup] {
        load([BillGroup].self, key: "xbill_groups") ?? []
    }

    // MARK: - Expenses

    func saveExpenses(_ expenses: [Expense], groupID: UUID) {
        save(expenses, key: "xbill_expenses_\(groupID)")
    }

    func loadExpenses(groupID: UUID) -> [Expense] {
        load([Expense].self, key: "xbill_expenses_\(groupID)") ?? []
    }

    // MARK: - Members

    func saveMembers(_ members: [User], groupID: UUID) {
        save(members, key: "xbill_members_\(groupID)")
    }

    func loadMembers(groupID: UUID) -> [User] {
        load([User].self, key: "xbill_members_\(groupID)") ?? []
    }

    // MARK: - Balance Summary (for Widget)

    func saveBalance(netBalance: Decimal, totalOwed: Decimal, totalOwing: Decimal, currency: String = "USD") {
        let defaults = CacheService.defaults
        // Store as String to preserve full Decimal precision (avoids Double rounding for large
        // amounts in JPY/IDR/etc.). Widget reads these back with Decimal(string:) → Double.
        defaults.set(netBalance.description, forKey: CacheService.netBalanceKey)
        defaults.set(totalOwed.description,  forKey: CacheService.totalOwedKey)
        defaults.set(totalOwing.description, forKey: CacheService.totalOwingKey)
        defaults.set(currency, forKey: CacheService.balanceCurrencyKey)
        defaults.set(true,     forKey: CacheService.balanceAvailableKey)
    }

    func loadNetBalance() -> Decimal {
        Decimal(string: CacheService.defaults.string(forKey: CacheService.netBalanceKey) ?? "") ?? .zero
    }

    func loadTotalOwed() -> Decimal {
        Decimal(string: CacheService.defaults.string(forKey: CacheService.totalOwedKey) ?? "") ?? .zero
    }

    func loadTotalOwing() -> Decimal {
        Decimal(string: CacheService.defaults.string(forKey: CacheService.totalOwingKey) ?? "") ?? .zero
    }

    func loadBalanceCurrency() -> String {
        CacheService.defaults.string(forKey: CacheService.balanceCurrencyKey) ?? "USD"
    }

    func loadBalanceAvailable() -> Bool {
        CacheService.defaults.object(forKey: CacheService.balanceAvailableKey) != nil
    }

    // MARK: - Encryption helpers
    //
    // Sensitive keys (groups, expenses, members, notifications) are AES-GCM encrypted
    // before writing to the App Group UserDefaults container. The encryption key lives
    // in Keychain with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly so it is never
    // included in device backups and cannot be migrated to another device.
    //
    // Balance summary keys (widget-readable) are intentionally left unencrypted: they
    // contain only 3 decimal numbers already visible in the widget on the home screen.

    static func encrypt(_ data: Data) -> Data? {
        guard let key = try? KeychainManager.shared.cacheEncryptionKey() else { return nil }
        return try? AES.GCM.seal(data, using: key).combined
    }

    static func decrypt(_ data: Data) -> Data? {
        guard let key = try? KeychainManager.shared.cacheEncryptionKey() else { return nil }
        guard let box = try? AES.GCM.SealedBox(combined: data) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    // MARK: - Helpers

    private func save<T: Encodable>(_ value: T, key: String) {
        // JSONEncoder is not thread-safe; create a new instance per call.
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        guard let plain = try? enc.encode(value) else { return }
        let data = CacheService.encrypt(plain) ?? plain
        CacheService.defaults.set(data, forKey: key)
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let raw = CacheService.defaults.data(forKey: key) else { return nil }
        // Attempt decryption; fall back to raw for seamless migration from unencrypted cache.
        let data = CacheService.decrypt(raw) ?? raw
        // JSONDecoder is not thread-safe; create a new instance per call.
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        return try? dec.decode(type, from: data)
    }
}
