//
//  GroupViewModelMaintenanceTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  `createDueRecurringInstances` and the archive pair were 0% covered — and recurring
//  instantiation is the function behind two of this project's worst defects: CRIT-01 (one
//  failing expense aborted the whole batch, so later templates were silently never created) and
//  CRIT-16 (the new instance copied the template's recurrence, so it re-instantiated forever).
//  Both are money-creating paths that nothing asserted.
//

import Testing
import Foundation
@testable import xBill

@Suite("GroupViewModel maintenance")
@MainActor
struct GroupViewModelMaintenanceTests {

    private func makeGroup(archived: Bool = false) -> BillGroup {
        BillGroup(id: UUID(), name: "Trip", emoji: "✈️", createdBy: UUID(),
                  isArchived: archived, currency: "USD", createdAt: Date())
    }

    private func recurringTemplate(
        id: UUID = UUID(),
        groupID: UUID,
        recurrence: Expense.Recurrence,
        nextOccurrence: Date?
    ) -> Expense {
        Expense(id: id, groupID: groupID, title: "Rent", amount: 1200, currency: "USD",
                payerID: UUID(), category: .utilities, notes: nil, receiptURL: nil,
                originalAmount: nil, originalCurrency: nil, recurrence: recurrence,
                nextOccurrenceDate: nextOccurrence, createdAt: Date())
    }

    private func makeVM(group: BillGroup,
                        groupService: FakeGroupService = FakeGroupService(),
                        expenseService: FakeExpenseService,
                        connected: Bool = true) -> GroupViewModel {
        GroupViewModel(group: group, groupService: groupService, expenseService: expenseService,
                       settlementService: FakeSettlementService(),
                       currentUserIDProvider: { UUID() },
                       isConnectedProvider: { connected })
    }

    // MARK: - Recurring instantiation

    /// CRIT-01: instantiation used to run in a throwing task group, so the first failure aborted
    /// the batch and every later template was silently skipped — a rent expense simply never
    /// appearing that month, with no error anywhere.
    @Test("One failing template does not stop the others")
    func oneFailureDoesNotAbortTheBatch() async {
        let group = makeGroup()
        let expenses = FakeExpenseService()
        let failing = UUID(), following = UUID()
        let due = Date(timeIntervalSince1970: 1_700_000_000)
        expenses.dueRecurring = [
            recurringTemplate(id: failing,   groupID: group.id, recurrence: .monthly, nextOccurrence: due),
            recurringTemplate(id: following, groupID: group.id, recurrence: .monthly, nextOccurrence: due)
        ]
        expenses.recurringFailures = [failing]

        await makeVM(group: group, expenseService: expenses).createDueRecurringInstances()

        #expect(expenses.recurringAttempts.map(\.templateID) == [failing, following],
                "A template that fails must not prevent the next one being attempted.")
    }

    /// CRIT-16: the occurrence handed to the backend must be the template's date *advanced* by its
    /// recurrence. Passing the unadvanced date re-instantiates the same occurrence forever.
    @Test("The new occurrence is advanced by the recurrence, not repeated")
    func advancesTheOccurrence() async {
        let group = makeGroup()
        let expenses = FakeExpenseService()
        let due = Date(timeIntervalSince1970: 1_700_000_000)
        expenses.dueRecurring = [recurringTemplate(groupID: group.id, recurrence: .monthly, nextOccurrence: due)]

        await makeVM(group: group, expenseService: expenses).createDueRecurringInstances()

        let attempt = try! #require(expenses.recurringAttempts.first)
        #expect(attempt.expected == due, "The claim must target the occurrence being consumed.")
        #expect(attempt.newNext > due, "The next occurrence must move forward or this repeats forever.")
        #expect(attempt.newNext == Expense.Recurrence.monthly.nextDate(from: due))
    }

    @Test("Templates with no recurrence or no due date are skipped")
    func skipsIneligibleTemplates() async {
        let group = makeGroup()
        let expenses = FakeExpenseService()
        let due = Date(timeIntervalSince1970: 1_700_000_000)
        expenses.dueRecurring = [
            recurringTemplate(groupID: group.id, recurrence: .none,    nextOccurrence: due),
            recurringTemplate(groupID: group.id, recurrence: .monthly, nextOccurrence: nil)
        ]

        await makeVM(group: group, expenseService: expenses).createDueRecurringInstances()

        #expect(expenses.recurringAttempts.isEmpty,
                "Neither a non-recurring expense nor one with no due date should be instantiated.")
    }

    @Test("Offline, no recurring work is attempted at all")
    func offlineDoesNothing() async {
        let group = makeGroup()
        let expenses = FakeExpenseService()
        expenses.dueRecurring = [recurringTemplate(groupID: group.id, recurrence: .weekly,
                                                   nextOccurrence: Date(timeIntervalSince1970: 1))]

        await makeVM(group: group, expenseService: expenses, connected: false).createDueRecurringInstances()

        #expect(expenses.recurringAttempts.isEmpty)
    }

    /// A failed *fetch* must stay quiet: this runs unprompted on entering a group, and an alert
    /// for background maintenance the user never asked for would be noise.
    @Test("A failed fetch raises no alert")
    func failedFetchIsQuiet() async {
        let group = makeGroup()
        let expenses = FakeExpenseService()
        expenses.dueRecurringError = AppError.networkUnavailable

        let vm = makeVM(group: group, expenseService: expenses)
        await vm.createDueRecurringInstances()

        #expect(vm.errorAlert == nil, "Background maintenance must not interrupt the user.")
    }

    // MARK: - Archive / unarchive

    @Test("Archiving flips the flag and drops the group from the active cache")
    func archiveUpdatesFlagAndCache() async {
        let group = makeGroup()
        CacheService.shared.saveGroups([group])
        let groups = FakeGroupService()

        let vm = makeVM(group: group, groupService: groups, expenseService: FakeExpenseService())
        await vm.archiveGroup()

        #expect(vm.group.isArchived)
        #expect(groups.updatedGroups.last?.isArchived == true, "The archived flag must reach the server.")
        #expect(!CacheService.shared.loadGroups().contains { $0.id == group.id },
                "An archived group must leave the active cache or it reappears offline.")
    }

    @Test("Unarchiving restores the group to the active cache")
    func unarchiveRestoresToCache() async {
        let group = makeGroup(archived: true)
        CacheService.shared.saveGroups([])
        let groups = FakeGroupService()

        let vm = makeVM(group: group, groupService: groups, expenseService: FakeExpenseService())
        await vm.unarchiveGroup()

        #expect(!vm.group.isArchived)
        #expect(CacheService.shared.loadGroups().contains { $0.id == group.id })
    }

    /// A refused archive must not leave the UI claiming the group is archived.
    @Test("A failed archive surfaces an alert and leaves the group unarchived")
    func failedArchiveDoesNotLie() async {
        let group = makeGroup()
        let groups = FakeGroupService()
        groups.updateGroupError = AppError.permissionDenied

        let vm = makeVM(group: group, groupService: groups, expenseService: FakeExpenseService())
        await vm.archiveGroup()

        #expect(!vm.group.isArchived, "The local flag must not move when the write failed.")
        #expect(vm.errorAlert != nil, "A refused archive is a user-visible failure.")
    }
}
