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
        await withTaskGroup(of: [NotificationItem].self) { taskGroup in
            for group in groups {
                taskGroup.addTask { await self.items(for: group) }
            }
            for await groupItems in taskGroup {
                fetched.append(contentsOf: groupItems)
            }
        }

        store.merge(fetched)

        return store.loadAll()
            .prefix(limit)
            .map { $0 }
    }

    private func items(for group: BillGroup) async -> [NotificationItem] {
        async let expensesTask = expenseService.fetchExpenses(groupID: group.id)
        async let membersTask  = groupService.fetchMembers(groupID: group.id)
        guard let expenses = try? await expensesTask,
              let members  = try? await membersTask else { return [] }

        let nameMap = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.displayName) })
        return expenses.map { expense in
            NotificationItem.expense(
                expense,
                payerName: nameMap[expense.payerID] ?? "Someone",
                groupName: group.name,
                groupEmoji: group.emoji
            )
        }
    }
}
