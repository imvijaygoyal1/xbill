//
//  CacheService.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation

// MARK: - CacheService
// Persists groups, expenses, and members to UserDefaults for offline reading.
// Dates encoded as secondsSince1970 to avoid ISO8601 fractional-second edge cases.

// MARK: - Cached balance keys (for Widget access)
extension CacheService {
    static let netBalanceKey   = "xbill_net_balance"
    static let totalOwedKey    = "xbill_total_owed"
    static let totalOwingKey   = "xbill_total_owing"
}

final class CacheService: Sendable {
    static let shared = CacheService()
    private init() {}

    // Prefer shared App Group suite so widgets can read cached data.
    // Falls back to UserDefaults.standard when the group isn't registered yet.
    // nonisolated(unsafe) is correct here: UserDefaults is thread-safe at runtime.
    nonisolated(unsafe) static let defaults: UserDefaults = UserDefaults(suiteName: "group.com.vijaygoyal.xbill") ?? .standard

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

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

    func saveBalance(netBalance: Decimal, totalOwed: Decimal, totalOwing: Decimal) {
        let defaults = CacheService.defaults
        defaults.set(Double(truncating: netBalance as NSDecimalNumber),   forKey: CacheService.netBalanceKey)
        defaults.set(Double(truncating: totalOwed as NSDecimalNumber),    forKey: CacheService.totalOwedKey)
        defaults.set(Double(truncating: totalOwing as NSDecimalNumber),   forKey: CacheService.totalOwingKey)
    }

    func loadNetBalance() -> Decimal {
        Decimal(CacheService.defaults.double(forKey: CacheService.netBalanceKey))
    }

    func loadTotalOwed() -> Decimal {
        Decimal(CacheService.defaults.double(forKey: CacheService.totalOwedKey))
    }

    func loadTotalOwing() -> Decimal {
        Decimal(CacheService.defaults.double(forKey: CacheService.totalOwingKey))
    }

    // MARK: - Helpers

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        CacheService.defaults.set(data, forKey: key)
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = CacheService.defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
