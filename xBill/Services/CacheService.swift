import Foundation

// MARK: - CacheService
// Persists groups, expenses, and members to UserDefaults for offline reading.
// Dates encoded as secondsSince1970 to avoid ISO8601 fractional-second edge cases.

final class CacheService: Sendable {
    static let shared = CacheService()
    private init() {}

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

    // MARK: - Helpers

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
