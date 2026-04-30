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

    private init() {}

    func fetchRecentActivity(userID: UUID, limit: Int = 50) async throws -> [ActivityItem] {
        let groups = try await groupService.fetchGroups(for: userID)

        var items: [ActivityItem] = []
        await withTaskGroup(of: [ActivityItem].self) { taskGroup in
            for group in groups {
                taskGroup.addTask { await self.items(for: group) }
            }
            for await groupItems in taskGroup {
                items.append(contentsOf: groupItems)
            }
        }

        return items
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    private func items(for group: BillGroup) async -> [ActivityItem] {
        async let expensesTask = expenseService.fetchExpenses(groupID: group.id)
        async let membersTask  = groupService.fetchMembers(groupID: group.id)
        guard let expenses = try? await expensesTask,
              let members  = try? await membersTask else { return [] }

        let nameMap = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.displayName) })
        return expenses.map { expense in
            ActivityItem(
                id:           expense.id,
                expenseTitle: expense.title,
                amount:       expense.amount,
                currency:     expense.currency,
                category:     expense.category,
                payerName:    nameMap[expense.payerID] ?? "Someone",
                groupName:    group.name,
                groupEmoji:   group.emoji,
                createdAt:    expense.createdAt
            )
        }
    }
}
