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

/// The extra surface `HomeViewModel` needs, on top of what `GroupViewModel` uses.
///
/// HOME-01: `HomeViewModel` had **no `init` at all** — `GroupService.shared`,
/// `ExpenseService.shared` and `AuthService.shared` were stored properties, `SettlementService`
/// and `NetworkMonitor` were reached through `.shared` inline, and no test in the target could
/// construct the type. `loadAll` — the screen every user lands on, and the one carrying the
/// cross-group balance arithmetic — had zero unit coverage.
///
/// These refine the existing protocols rather than widening them, so `FakeGroupService`,
/// `FakeExpenseService` and `ActivityServiceTests.StubGroups` are untouched: a fake only has to
/// implement the extra methods if it is standing in for Home.
@MainActor
protocol HomeGroupDataProviding: GroupDataProviding {
    func fetchArchivedGroups(for userID: UUID) async throws -> [BillGroup]
    func createGroup(name: String, emoji: String, currency: String, createdBy: UUID) async throws -> BillGroup
    func deleteGroup(groupId: UUID) async throws
    func groupChanges(userID: UUID, groupIDs: [UUID]) async throws -> AsyncStream<Void>
}

@MainActor
protocol HomeExpenseDataProviding: ExpenseDataProviding {
    /// Spelled out in full because a protocol requirement cannot carry default arguments — the
    /// concrete `ExpenseService.createExpense` defaults its last four, and a witness matches on
    /// the whole signature regardless. The convenience below restores the short form for callers.
    func createExpense(
        groupID: UUID, title: String, amount: Decimal, currency: String,
        payerID: UUID, category: Expense.Category, notes: String?, splits: [SplitInput],
        originalAmount: Decimal?, originalCurrency: String?,
        recurrence: Expense.Recurrence, nextOccurrenceDate: Date?
    ) async throws -> Expense
}

extension HomeExpenseDataProviding {
    /// The eight-argument form the app actually calls. A separate arity, so it forwards to the
    /// requirement above rather than recursing into itself.
    func createExpense(
        groupID: UUID, title: String, amount: Decimal, currency: String,
        payerID: UUID, category: Expense.Category, notes: String?, splits: [SplitInput]
    ) async throws -> Expense {
        try await createExpense(
            groupID: groupID, title: title, amount: amount, currency: currency,
            payerID: payerID, category: category, notes: notes, splits: splits,
            originalAmount: nil, originalCurrency: nil,
            recurrence: .none, nextOccurrenceDate: nil)
    }
}

extension ExpenseService: ExpenseDataProviding {}
extension RemoteNotificationService: RemoteNotificationProviding {}
extension GroupService: GroupDataProviding {}
extension GroupService: HomeGroupDataProviding {}
extension ExpenseService: HomeExpenseDataProviding {}
