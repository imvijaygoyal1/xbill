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

// MARK: - Balance snapshot (for Widget access)

/// Single-key atomic balance snapshot written and read by both the app and widget.
/// Encoding all fields into one JSON blob under `xbill_balance_snapshot` avoids the
/// partial-state race that occurred when a widget read mid-write while the app was
/// setting five separate UserDefaults keys (L-27).
struct BalanceSnapshot: Codable {
    var net: String
    var owed: String
    var owing: String
    var currency: String
    var available: Bool
}

extension CacheService {
    static let balanceSnapshotKey = "xbill_balance_snapshot"

    // Legacy individual keys kept for migration-read only; no longer written.
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

    /// Atomically encodes all balance fields into a single JSON blob under one key.
    /// This prevents the widget from observing partial state while the main app is
    /// mid-write across multiple separate UserDefaults keys (L-27 fix).
    func saveBalance(netBalance: Decimal, totalOwed: Decimal, totalOwing: Decimal, currency: String = "USD") {
        let snapshot = BalanceSnapshot(
            net: netBalance.description,
            owed: totalOwed.description,
            owing: totalOwing.description,
            currency: currency,
            available: true
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        CacheService.defaults.set(data, forKey: CacheService.balanceSnapshotKey)
    }

    /// Loads the balance snapshot, falling back to the legacy individual keys for
    /// clients that wrote the old multi-key format before this migration.
    private func loadSnapshot() -> BalanceSnapshot? {
        if let data = CacheService.defaults.data(forKey: CacheService.balanceSnapshotKey),
           let snapshot = try? JSONDecoder().decode(BalanceSnapshot.self, from: data) {
            return snapshot
        }
        // Legacy fallback: if the new key is absent, read the old individual keys.
        guard CacheService.defaults.object(forKey: CacheService.balanceAvailableKey) != nil else {
            return nil
        }
        return BalanceSnapshot(
            net: CacheService.defaults.string(forKey: CacheService.netBalanceKey) ?? "0",
            owed: CacheService.defaults.string(forKey: CacheService.totalOwedKey) ?? "0",
            owing: CacheService.defaults.string(forKey: CacheService.totalOwingKey) ?? "0",
            currency: CacheService.defaults.string(forKey: CacheService.balanceCurrencyKey) ?? "USD",
            available: true
        )
    }

    func loadNetBalance() -> Decimal {
        Decimal(string: loadSnapshot()?.net ?? "") ?? .zero
    }

    func loadTotalOwed() -> Decimal {
        Decimal(string: loadSnapshot()?.owed ?? "") ?? .zero
    }

    func loadTotalOwing() -> Decimal {
        Decimal(string: loadSnapshot()?.owing ?? "") ?? .zero
    }

    func loadBalanceCurrency() -> String {
        loadSnapshot()?.currency ?? "USD"
    }

    func loadBalanceAvailable() -> Bool {
        loadSnapshot()?.available ?? false
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
        // M-03: if encryption fails (e.g. Keychain unavailable on first-unlock devices),
        // skip the write entirely rather than persisting plaintext financial data.
        guard let data = CacheService.encrypt(plain) else { return }
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
