//
//  ActivityService.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation

final class ActivityService: Sendable {
    static let shared = ActivityService()
    private let groupService   = GroupService.shared
    private let expenseService = ExpenseService.shared
    private let store          = NotificationStore.shared

    private init() {}

    /// Fetches fresh expense activity from the DB, merges into the local store,
    /// then returns the combined list sorted newest-first.
    /// Items already in the store keep their existing read state.
    func fetchRecentActivity(userID: UUID, limit: Int = 50) async throws -> [NotificationItem] {
        let groups = try await groupService.fetchGroups(for: userID)

        var fetched: [NotificationItem] = []
        var groupErrors: [Error] = []
        await withTaskGroup(of: Result<[NotificationItem], Error>.self) { taskGroup in
            for group in groups {
                taskGroup.addTask { await self.items(for: group) }
            }
            for await result in taskGroup {
                switch result {
                case .success(let items): fetched.append(contentsOf: items)
                case .failure(let err):   groupErrors.append(err)
                }
            }
        }
        // Surface the first group-level error rather than silently swallowing it;
        // caller sees partial results plus the error so it can display a warning.
        if fetched.isEmpty, let first = groupErrors.first { throw first }

        store.merge(fetched)

        return store.loadAll()
            .prefix(limit)
            .map { $0 }
    }

    private func items(for group: BillGroup) async -> Result<[NotificationItem], Error> {
        do {
            async let expensesTask = expenseService.fetchExpenses(groupID: group.id, limit: 50)
            async let membersTask  = groupService.fetchMembers(groupID: group.id)
            let expenses = try await expensesTask
            let members  = try await membersTask
            let nameMap  = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.displayName) })
            let items = expenses.map { expense in
                NotificationItem.expense(
                    expense,
                    payerName: expense.payerID.flatMap { nameMap[$0] } ?? "Someone",
                    groupName: group.name,
                    groupEmoji: group.emoji
                )
            }
            return .success(items)
        } catch {
            return .failure(error)
        }
    }
}
