//
//  GroupViewModelStateTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  Senior review of 2026-07-28, REV-02 … REV-05. Every one of these paths went through a
//  `.shared` singleton, so none of them could be exercised before `GroupDataProviding` /
//  `ExpenseDataProviding` were introduced.
//

import Foundation
import Testing
@testable import xBill

// MARK: - Fakes

@MainActor
final class FakeExpenseService: ExpenseDataProviding {
    var expenses: [Expense] = []
    var splits: [Split] = []
    /// Split ids that `settleSplit` should reject.
    var failingSplitIDs: Set<UUID> = []
    var settledSplitIDs: [UUID] = []
    var deletedExpenseIDs: [UUID] = []
    var fetchSplitsError: Error?
    var notifyCount = 0

    func fetchExpenses(groupID: UUID, limit: Int?) async throws -> [Expense] { expenses }

    func fetchSplits(expenseIDs: [UUID]) async throws -> [Split] {
        if let fetchSplitsError { throw fetchSplitsError }
        return splits.filter { expenseIDs.contains($0.expenseID) }
    }

    func settleSplit(id: UUID) async throws {
        if failingSplitIDs.contains(id) {
            throw AppError.permissionDenied
        }
        settledSplitIDs.append(id)
        if let index = splits.firstIndex(where: { $0.id == id }) {
            splits[index].isSettled = true
        }
    }

    func deleteExpense(id: UUID) async throws {
        deletedExpenseIDs.append(id)
        expenses.removeAll { $0.id == id }
    }

    func updateExpense(_ expense: Expense) async throws -> Expense { expense }
    func fetchDueRecurringExpenses(groupID: UUID) async throws -> [Expense] { [] }
    func createRecurringInstance(templateID: UUID, expectedNextOccurrence: Date, newNextOccurrence: Date) async throws -> Expense? { nil }
    func notifySettlementRecorded(settlementID: UUID, groupID: UUID, toUserID: UUID, amount: Decimal, currency: String) async {
        notifyCount += 1
    }
}

@MainActor
final class FakeGroupService: GroupDataProviding {
    var members: [User] = []
    func fetchMembers(groupID: UUID, includeInactive: Bool) async throws -> [User] { members }
    func addMember(groupId: UUID, userId: UUID) async throws {}
    func removeMember(groupId: UUID, userId: UUID) async throws {}
    func updateGroup(_ group: BillGroup) async throws -> BillGroup { group }
}

// MARK: - Fixtures

@MainActor
private func makeGroup() -> BillGroup {
    BillGroup(id: UUID(), name: "Trip", emoji: "✈️", createdBy: UUID(), isArchived: false, currency: "USD", createdAt: Date())
}

@MainActor
private func makeExpense(id: UUID = UUID(), payerID: UUID, groupID: UUID, amount: Decimal = 30) -> Expense {
    Expense(
        id: id, groupID: groupID, title: "Dinner", amount: amount, currency: "USD",
        payerID: payerID, category: .food, notes: nil, receiptURL: nil,
        originalAmount: nil, originalCurrency: nil, recurrence: .none,
        nextOccurrenceDate: nil, createdAt: Date()
    )
}

@MainActor
private func makeSplit(expenseID: UUID, userID: UUID, amount: Decimal) -> Split {
    Split(id: UUID(), expenseID: expenseID, userID: userID, amount: amount, isSettled: false, settledAt: nil)
}

// MARK: - REV-02

@Suite("Settlement partial failure", .serialized)
@MainActor
struct SettlementPartialFailureTests {

    /// REV-02. Splits are settled in a parallel task group; if one write fails the group
    /// throws, but the writes that already committed stand. The view model showed a generic
    /// error and recorded nothing locally, so its state disagreed with the server.
    @Test("A partial failure keeps the committed splits and reports what happened")
    func partialFailureIsReported() async {
        let group = makeGroup()
        let payer = UUID(), debtor = UUID()
        let expense = makeExpense(payerID: payer, groupID: group.id)

        let expenseService = FakeExpenseService()
        let groupService = FakeGroupService()
        expenseService.expenses = [expense]
        let good = makeSplit(expenseID: expense.id, userID: debtor, amount: 10)
        let bad  = makeSplit(expenseID: expense.id, userID: debtor, amount: 10)
        expenseService.splits = [good, bad]
        expenseService.failingSplitIDs = [bad.id]

        let vm = GroupViewModel(group: group, groupService: groupService, expenseService: expenseService)
        vm.expenses = [expense]

        await vm.recordSettlement(SettlementSuggestion(
            id: UUID(), fromUserID: debtor, fromName: "D",
            toUserID: payer, toName: "P", amount: 20, currency: "USD"
        ))

        // The write that succeeded must not be rolled back locally — it is committed.
        #expect(expenseService.settledSplitIDs == [good.id])
        // The user has to be told the settlement was incomplete, not just "something went wrong".
        let message = vm.errorAlert?.message ?? ""
        #expect(vm.errorAlert != nil)
        #expect(message.contains("1 of 2") || message.contains("partially"))
    }

    @Test("A settlement where every write succeeds reports no error")
    func fullSuccessIsClean() async {
        let group = makeGroup()
        let payer = UUID(), debtor = UUID()
        let expense = makeExpense(payerID: payer, groupID: group.id)

        let expenseService = FakeExpenseService()
        expenseService.expenses = [expense]
        let split = makeSplit(expenseID: expense.id, userID: debtor, amount: 10)
        expenseService.splits = [split]

        let vm = GroupViewModel(group: group, groupService: FakeGroupService(), expenseService: expenseService)
        vm.expenses = [expense]

        await vm.recordSettlement(SettlementSuggestion(
            id: UUID(), fromUserID: debtor, fromName: "D",
            toUserID: payer, toName: "P", amount: 10, currency: "USD"
        ))

        #expect(expenseService.settledSplitIDs == [split.id])
        #expect(vm.errorAlert == nil)
    }
}

// MARK: - REV-03

@Suite("Deleted expense does not resurrect", .serialized)
@MainActor
struct DeletedExpenseTests {

    /// REV-03. `applyFetchedExpenses` re-merges any `locallyCreatedExpenses` entry missing
    /// from a fetch, and only clears an entry when it *appears* in a fetch. `deleteExpense`
    /// never removed it, so a just-deleted expense came back on the next load and stayed
    /// back for the life of the view model.
    @Test("An expense created then deleted locally does not come back on reload")
    func deletedLocalExpenseStaysDeleted() async {
        let group = makeGroup()
        let expenseService = FakeExpenseService()
        let groupService = FakeGroupService()
        let vm = GroupViewModel(group: group, groupService: groupService, expenseService: expenseService)

        let expense = makeExpense(payerID: UUID(), groupID: group.id)
        vm.recordCreatedExpense(expense)
        #expect(vm.expenses.contains { $0.id == expense.id })

        await vm.deleteExpense(expense)
        #expect(!vm.expenses.contains { $0.id == expense.id })

        // The server never knew about it, so the reload returns nothing.
        await vm.load(showError: false)

        #expect(!vm.expenses.contains { $0.id == expense.id })
    }
}

// MARK: - REV-04

@Suite("Stale-data flag survives the balance recompute", .serialized)
@MainActor
struct BalanceLoadFailedFlagTests {

    /// REV-04. `applyFetchedExpenses` raises `balanceLoadFailed` when a reload returns an
    /// empty list for a group known to have expenses. `load()` then called `computeBalances`,
    /// which cleared the flag before any view could read it — so the refresh state never
    /// rendered.
    @Test("An empty reload for a known non-empty group leaves the stale flag set")
    func emptyReloadKeepsFlag() async {
        let group = makeGroup()
        let expenseService = FakeExpenseService()
        let groupService = FakeGroupService()
        let vm = GroupViewModel(group: group, groupService: groupService, expenseService: expenseService)

        vm.expenses = [makeExpense(payerID: UUID(), groupID: group.id)]
        vm.hasKnownNonEmptyExpenses = true
        expenseService.expenses = []   // server returns nothing

        await vm.load(showError: false)

        #expect(vm.balanceLoadFailed)
        #expect(!vm.expenses.isEmpty)   // previous expenses are kept
    }

    @Test("A healthy reload clears the stale flag")
    func healthyReloadClearsFlag() async {
        let group = makeGroup()
        let expenseService = FakeExpenseService()
        let vm = GroupViewModel(group: group, groupService: FakeGroupService(), expenseService: expenseService)

        expenseService.expenses = [makeExpense(payerID: UUID(), groupID: group.id)]
        vm.balanceLoadFailed = true

        await vm.load(showError: false)

        #expect(!vm.balanceLoadFailed)
    }
}
