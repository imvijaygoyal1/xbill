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
    var deletedExpenseIDs: [UUID] = []
    var fetchSplitsError: Error?
    var notifyCount = 0
    /// Counts split fetches so a test can assert that recording or deleting a payment performs
    /// none. A fetch is a suspension point, and a suspension between the two mutations a
    /// payment makes is what crashed `UICollectionView` on device — see `applyDerivedBalances`.
    var fetchSplitsCount = 0

    func fetchExpenses(groupID: UUID, limit: Int?) async throws -> [Expense] { expenses }

    func fetchSplits(expenseIDs: [UUID]) async throws -> [Split] {
        fetchSplitsCount += 1
        if let fetchSplitsError { throw fetchSplitsError }
        return splits.filter { expenseIDs.contains($0.expenseID) }
    }

    func deleteExpense(id: UUID) async throws {
        deletedExpenseIDs.append(id)
        expenses.removeAll { $0.id == id }
    }

    func updateExpense(_ expense: Expense) async throws -> Expense { expense }

    // MARK: Recurring-expense seam
    var dueRecurring: [Expense] = []
    var dueRecurringError: Error?
    /// Template ids whose instantiation was *attempted*, in order. CRIT-01 was that one failure
    /// aborted the whole batch, so which ids are reached is the assertion that matters.
    var recurringAttempts: [(templateID: UUID, expected: Date, newNext: Date)] = []
    /// Template ids that should throw when instantiated.
    var recurringFailures: Set<UUID> = []

    func fetchDueRecurringExpenses(groupID: UUID) async throws -> [Expense] {
        if let dueRecurringError { throw dueRecurringError }
        return dueRecurring
    }

    func createRecurringInstance(templateID: UUID, expectedNextOccurrence: Date, newNextOccurrence: Date) async throws -> Expense? {
        recurringAttempts.append((templateID, expectedNextOccurrence, newNextOccurrence))
        if recurringFailures.contains(templateID) {
            throw AppError.serverError("instantiation refused")
        }
        return nil
    }
    func notifySettlementRecorded(settlementID: UUID) async {
        notifyCount += 1
    }
}

@MainActor
final class FakeGroupService: GroupDataProviding {
    var members: [User] = []
    func fetchMembers(groupID: UUID, includeInactive: Bool) async throws -> [User] { members }
    func addMember(groupId: UUID, userId: UUID) async throws {}
    func removeMember(groupId: UUID, userId: UUID) async throws {}
    var updateGroupError: Error?
    private(set) var updatedGroups: [BillGroup] = []
    func updateGroup(_ group: BillGroup) async throws -> BillGroup {
        if let updateGroupError { throw updateGroupError }
        updatedGroups.append(group)
        return group
    }
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
        let vm = GroupViewModel(group: group, groupService: groupService, expenseService: expenseService,
                                settlementService: FakeSettlementService())

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
        let vm = GroupViewModel(group: group, groupService: groupService, expenseService: expenseService,
                                settlementService: FakeSettlementService())

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
        let vm = GroupViewModel(group: group, groupService: FakeGroupService(), expenseService: expenseService,
                                settlementService: FakeSettlementService())

        expenseService.expenses = [makeExpense(payerID: UUID(), groupID: group.id)]
        vm.balanceLoadFailed = true

        await vm.load(showError: false)

        #expect(!vm.balanceLoadFailed)
    }
}
