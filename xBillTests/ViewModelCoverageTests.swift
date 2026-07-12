//
//  ViewModelCoverageTests.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import Testing
@testable import xBill

private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

private func makeUser(
    _ name: String,
    id: UUID = UUID(),
    isActive: Bool = true
) -> User {
    User(
        id: id,
        email: "\(name.lowercased())@example.com",
        displayName: name,
        avatarURL: nil,
        isActive: isActive,
        createdAt: fixedDate
    )
}

private func makeCoverageGroup(
    id: UUID = UUID(),
    name: String = "Coverage Group",
    currency: String = "USD",
    isArchived: Bool = false
) -> BillGroup {
    BillGroup(
        id: id,
        name: name,
        emoji: "💸",
        createdBy: UUID(),
        isArchived: isArchived,
        currency: currency,
        createdAt: fixedDate
    )
}

private func makeExpense(
    id: UUID = UUID(),
    groupID: UUID,
    title: String,
    amount: Decimal = 10,
    currency: String = "USD",
    payerID: UUID? = UUID(),
    createdAt: Date = fixedDate
) -> Expense {
    Expense(
        id: id,
        groupID: groupID,
        title: title,
        amount: amount,
        currency: currency,
        payerID: payerID,
        category: .food,
        notes: nil,
        receiptURL: nil,
        originalAmount: nil,
        originalCurrency: nil,
        recurrence: .none,
        nextOccurrenceDate: nil,
        createdAt: createdAt
    )
}

@Suite("AddExpenseViewModel — Validation and Split State")
@MainActor
struct AddExpenseViewModelCoverageTests {

    @Test("Initial state uses group currency, current user payer, and all members included")
    func initialStateUsesGroupDefaults() {
        let currentUserID = UUID()
        let otherUserID = UUID()
        let group = makeCoverageGroup(currency: "EUR")
        let members = [
            makeUser("Alice", id: currentUserID),
            makeUser("Bob", id: otherUserID)
        ]

        let vm = AddExpenseViewModel(group: group, members: members, currentUserID: currentUserID)

        #expect(vm.currency == "EUR")
        #expect(vm.expenseCurrency == "EUR")
        #expect(vm.payerID == currentUserID)
        #expect(vm.splitInputs.map(\.userID) == [currentUserID, otherUserID])
        #expect(vm.splitInputs.filter { !$0.isIncluded }.isEmpty)
        #expect(!vm.canSave)
    }

    @Test("Amount parsing accepts POSIX decimals and comma decimal input")
    func amountParsingAcceptsCommonDecimalFormats() {
        let vm = AddExpenseViewModel(group: makeCoverageGroup(), members: [], currentUserID: UUID())

        vm.amountText = "12.34"
        #expect(vm.amount == Decimal(string: "12.34"))

        vm.amountText = "12,34"
        #expect(vm.amount == Decimal(string: "12.34"))

        vm.amountText = "not-a-number"
        #expect(vm.amount == .zero)
    }

    @Test("canSave requires title, positive amount, payer, included participant, and valid split")
    func canSaveRequiresRequiredFieldsAndValidSplit() {
        let currentUserID = UUID()
        let group = makeCoverageGroup()
        let vm = AddExpenseViewModel(
            group: group,
            members: [makeUser("Alice", id: currentUserID)],
            currentUserID: currentUserID
        )

        vm.title = " Dinner "
        vm.amountText = "24.00"
        vm.recomputeSplits()
        #expect(vm.canSave)

        vm.title = "   "
        #expect(!vm.canSave)

        vm.title = "Dinner"
        vm.payerID = nil
        #expect(!vm.canSave)

        vm.payerID = currentUserID
        vm.splitInputs[0].isIncluded = false
        #expect(!vm.canSave)
    }

    @Test("Exact split validation blocks save until split amounts match final amount")
    func exactSplitValidationControlsSave() {
        let currentUserID = UUID()
        let group = makeCoverageGroup()
        let vm = AddExpenseViewModel(
            group: group,
            members: [makeUser("Alice", id: currentUserID)],
            currentUserID: currentUserID
        )

        vm.title = "Dinner"
        vm.amountText = "20.00"
        vm.splitStrategy = .exact
        vm.splitInputs[0].amount = 10

        #expect(vm.splitValidationError != nil)
        #expect(!vm.canSave)

        vm.splitInputs[0].amount = 20

        #expect(vm.splitValidationError == nil)
        #expect(vm.canSave)
    }

    @Test("Equal split recompute ignores excluded participants and toggle recomputes")
    func equalSplitRecomputeRespectsIncludedParticipants() {
        let aliceID = UUID()
        let bobID = UUID()
        let caraID = UUID()
        let vm = AddExpenseViewModel(
            group: makeCoverageGroup(),
            members: [
                makeUser("Alice", id: aliceID),
                makeUser("Bob", id: bobID),
                makeUser("Cara", id: caraID)
            ],
            currentUserID: aliceID
        )

        vm.amountText = "30.00"
        vm.recomputeSplits()

        #expect(vm.splitInputs.map(\.amount) == [10, 10, 10])

        vm.toggle(participantID: caraID)

        #expect(vm.splitInputs[0].amount == 15)
        #expect(vm.splitInputs[1].amount == 15)
        #expect(vm.splitInputs[2].amount == .zero)
        #expect(!vm.splitInputs[2].isIncluded)
    }

    @Test("Foreign currency requires conversion before save can be enabled")
    func foreignCurrencyRequiresConvertedAmount() {
        let currentUserID = UUID()
        let vm = AddExpenseViewModel(
            group: makeCoverageGroup(currency: "USD"),
            members: [makeUser("Alice", id: currentUserID)],
            currentUserID: currentUserID
        )

        vm.title = "Dinner"
        vm.amountText = "10.00"
        vm.expenseCurrency = "EUR"
        vm.convertedAmount = nil

        #expect(vm.isForeignCurrency)
        #expect(vm.finalAmount == .zero)
        #expect(!vm.canSave)

        vm.convertedAmount = 11.25
        vm.recomputeSplits()

        #expect(vm.finalAmount == 11.25)
        #expect(vm.canSave)
        #expect(vm.splitInputs[0].amount == 11.25)
    }
}

@Suite("GroupViewModel — Local State")
@MainActor
struct GroupViewModelCoverageTests {

    @Test("Computed member and expense views are deterministic")
    func computedViewsAreDeterministic() {
        let group = makeCoverageGroup()
        let activeID = UUID()
        let inactiveID = UUID()
        let older = makeExpense(
            groupID: group.id,
            title: "Older",
            createdAt: fixedDate
        )
        let newer = makeExpense(
            groupID: group.id,
            title: "Newer",
            createdAt: fixedDate.addingTimeInterval(60)
        )
        let vm = GroupViewModel(group: group)
        vm.members = [
            makeUser("Active", id: activeID, isActive: true),
            makeUser("Inactive", id: inactiveID, isActive: false)
        ]
        vm.expenses = [older, newer]
        vm.balances = [activeID: 12.50]

        #expect(vm.memberNames[activeID] == "Active")
        #expect(vm.activeMembers.map(\.id) == [activeID])
        #expect(vm.sortedExpenses.map(\.title) == ["Newer", "Older"])
        #expect(vm.balance(for: activeID) == 12.50)
        #expect(vm.balance(for: inactiveID) == .zero)
        #expect(!vm.canChangeCurrency)
    }

    @Test("recordCreatedExpense appends once and preserves existing expenses")
    func recordCreatedExpenseAppendsOnce() {
        let group = makeCoverageGroup()
        let existing = makeExpense(groupID: group.id, title: "Existing")
        let created = makeExpense(groupID: group.id, title: "Created")
        let vm = GroupViewModel(group: group)
        vm.expenses = [existing]

        vm.recordCreatedExpense(created)
        vm.recordCreatedExpense(created)

        #expect(vm.expenses.map(\.id) == [existing.id, created.id])
        #expect(vm.expenses.filter { $0.id == created.id }.count == 1)
    }

    @Test("canChangeCurrency is true only before expenses are present")
    func canChangeCurrencyDependsOnExpenses() {
        let group = makeCoverageGroup(currency: "USD")
        let vm = GroupViewModel(group: group)

        #expect(vm.canChangeCurrency)

        vm.recordCreatedExpense(makeExpense(groupID: group.id, title: "Coffee"))

        #expect(!vm.canChangeCurrency)
    }
}
