//
//  GroupDataProviding.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  Injection seams for `GroupViewModel`. The view model owns the state machine that decides
//  what is settled, what is cached and when balances are recomputed — the part that has
//  produced real money-correctness defects (REV-02 … REV-05) — but every one of those paths
//  went through a `.shared` singleton, so none of it could be exercised without a live
//  PostgREST endpoint.
//
//  Mirrors the seam already used by `ActivityViewModel`.
//

import Foundation

/// The expense/split operations `GroupViewModel` depends on.
@MainActor
protocol ExpenseDataProviding: AnyObject, Sendable {
    func fetchExpenses(groupID: UUID, limit: Int?) async throws -> [Expense]
    func fetchSplits(expenseIDs: [UUID]) async throws -> [Split]
    func deleteExpense(id: UUID) async throws
    func updateExpense(_ expense: Expense) async throws -> Expense
    func fetchDueRecurringExpenses(groupID: UUID) async throws -> [Expense]
    func createRecurringInstance(
        templateID: UUID,
        expectedNextOccurrence: Date,
        newNextOccurrence: Date
    ) async throws -> Expense?
    func notifySettlementRecorded(settlementID: UUID) async
}

/// The group/member operations `GroupViewModel` depends on.
@MainActor
protocol GroupDataProviding: AnyObject, Sendable {
    /// Needed by `ActivityService`, which derives historical expense activity per group.
    func fetchGroups(for userID: UUID) async throws -> [BillGroup]
    func fetchMembers(groupID: UUID, includeInactive: Bool) async throws -> [User]
    func addMember(groupId: UUID, userId: UUID) async throws
    func removeMember(groupId: UUID, userId: UUID) async throws
    func updateGroup(_ group: BillGroup) async throws -> BillGroup
}

/// The `public.notifications` surface `ActivityService` depends on.
///
/// Added so `ActivityService` can be tested at all: it held four hard-coded singletons and sat at
/// 27.7% coverage, with `fetchLegacyExpenseActivity`, `reconcilePendingReadStates`,
/// `fetchRecentActivity` and `items(for:)` entirely unreachable from tests.
protocol RemoteNotificationProviding: AnyObject, Sendable {
    func fetch(userID: UUID, limit: Int) async throws -> [NotificationItem]
    func markRead(id: UUID) async throws
    func markUnread(id: UUID) async throws
    func markAllRead(userID: UUID) async throws
    func delete(id: UUID) async throws
}

extension ExpenseService: ExpenseDataProviding {}
extension RemoteNotificationService: RemoteNotificationProviding {}
extension GroupService: GroupDataProviding {}
