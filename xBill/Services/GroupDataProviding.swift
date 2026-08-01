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
    func fetchMembers(groupID: UUID, includeInactive: Bool) async throws -> [User]
    func addMember(groupId: UUID, userId: UUID) async throws
    func removeMember(groupId: UUID, userId: UUID) async throws
    func updateGroup(_ group: BillGroup) async throws -> BillGroup
}

extension ExpenseService: ExpenseDataProviding {}
extension GroupService: GroupDataProviding {}
