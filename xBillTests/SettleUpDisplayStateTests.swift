//
//  SettleUpDisplayStateTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  Residual fix for the settlements-ledger branch (2026-07-28), R1 + R2.
//
//  R1: `GroupDetailView.shouldShowBalanceErrorState` requires `settlementSuggestions.isEmpty`,
//  so the stale-data warning it was meant to drive could never appear in the one case that
//  matters — a settlements fetch failure with a *non-empty* suggestions list, which is exactly
//  when a debt can render at its gross, pre-payment amount with a Record Payment button still
//  showing. `GroupViewModel.settlementsMayBeStale` is the new, separate condition; the existing
//  error-state predicate is untouched and is now `GroupViewModel.settleUpErrorStateShouldShow`.
//
//  R2: the offline branch of `load()` never touched `settlements` or `balanceLoadFailed`, so a
//  fresh view model opened offline — `CacheService` has no settlements persistence — showed
//  gross balances with no warning at all, not even the (wrong) one R1 describes.
//
//  Every assertion below is about the *rendered decision* (`settlementsMayBeStale`,
//  `settleUpErrorStateShouldShow`), not about `balanceLoadFailed` in isolation — asserting only
//  the flag is exactly the shape of test that let R1 ship with a passing suite.
//

import Foundation
import Testing
@testable import xBill

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

@Suite("Settle Up display decision", .serialized)
@MainActor
struct SettleUpDisplayStateTests {

    // MARK: - R1: settlements fetch fails, suggestions non-empty

    @Test("A settlements fetch failure with suggestions on screen shows the stale warning, not the empty-list error state")
    func fetchFailureWithSuggestionsShowsWarning() async {
        let group = makeGroup(); let alice = UUID(); let bob = UUID()
        let expenses = FakeExpenseService(); let settlements = FakeSettlementService()
        let e = makeExpense(payerID: alice, groupID: group.id)
        expenses.expenses = [e]
        expenses.splits = [makeSplit(expenseID: e.id, userID: bob, amount: 10)]
        settlements.fetchError = AppError.networkUnavailable
        // The catch branch of `load()` never assigns `expenses` from the failed fetch tuple —
        // it restores from `CacheService`, so this mirrors a relaunch (or a later reload) where
        // an earlier successful load already cached this group's expenses. Directly seeding the
        // cache is the standalone equivalent of `settlementsFetchFailureRaisesBalanceLoadFailed`
        // running a healthy load first.
        CacheService.shared.saveExpenses([e], groupID: group.id)

        let vm = GroupViewModel(group: group, groupService: FakeGroupService(),
                                expenseService: expenses, settlementService: settlements,
                                currentUserIDProvider: { bob },
                                isConnectedProvider: { true })
        await vm.load(showError: false)

        #expect(vm.balanceLoadFailed)
        #expect(!vm.settlementSuggestions.isEmpty)
        #expect(vm.settlementsMayBeStale)
        // The predicate this replaces must stay false here — a non-empty list must not be
        // hidden behind the full-screen error/retry state.
        #expect(!vm.settleUpErrorStateShouldShow)
    }

    // MARK: - Healthy load, suggestions non-empty

    @Test("A healthy load with suggestions on screen shows no warning")
    func healthyLoadWithSuggestionsShowsNoWarning() async {
        let group = makeGroup(); let alice = UUID(); let bob = UUID()
        let expenses = FakeExpenseService(); let settlements = FakeSettlementService()
        let e = makeExpense(payerID: alice, groupID: group.id)
        expenses.expenses = [e]
        expenses.splits = [makeSplit(expenseID: e.id, userID: bob, amount: 10)]

        let vm = GroupViewModel(group: group, groupService: FakeGroupService(),
                                expenseService: expenses, settlementService: settlements,
                                currentUserIDProvider: { bob },
                                isConnectedProvider: { true })
        await vm.load(showError: false)

        #expect(!vm.settlementSuggestions.isEmpty)
        #expect(!vm.balanceLoadFailed)
        #expect(!vm.settlementsMayBeStale)
        #expect(!vm.settleUpErrorStateShouldShow)
    }

    // MARK: - R2: offline, no cached settlements, non-empty group

    @Test("Offline with no cached settlements and a non-empty group shows the warning")
    func offlineNoCachedSettlementsShowsWarning() async {
        let group = makeGroup(); let alice = UUID(); let bob = UUID()
        let expenses = FakeExpenseService(); let settlements = FakeSettlementService()
        let e = makeExpense(payerID: alice, groupID: group.id)
        expenses.expenses = [e]
        expenses.splits = [makeSplit(expenseID: e.id, userID: bob, amount: 10)]
        // Mirrors an earlier successful online load having cached expenses for this group —
        // CacheService has no settlements persistence, so `settlements` starts empty regardless.
        CacheService.shared.saveExpenses([e], groupID: group.id)

        let vm = GroupViewModel(group: group, groupService: FakeGroupService(),
                                expenseService: expenses, settlementService: settlements,
                                currentUserIDProvider: { bob },
                                isConnectedProvider: { false })
        await vm.load(showError: false)

        #expect(vm.settlements.isEmpty)
        #expect(vm.balanceLoadFailed)
        #expect(!vm.settlementSuggestions.isEmpty)
        #expect(vm.settlementsMayBeStale)
    }

    @Test("Offline with settlements already in memory does not raise a spurious warning")
    func offlineWithInMemorySettlementsShowsNoWarning() async {
        // An earlier *online* load in this session already populated `settlements` — going
        // offline afterward must not treat a real, already-loaded ledger as missing.
        let group = makeGroup(); let alice = UUID(); let bob = UUID()
        let expenses = FakeExpenseService(); let settlements = FakeSettlementService()
        let e = makeExpense(payerID: alice, groupID: group.id)
        expenses.expenses = [e]
        expenses.splits = [makeSplit(expenseID: e.id, userID: bob, amount: 10)]
        let repayment = Settlement(id: UUID(), groupID: group.id, fromUserID: bob, toUserID: alice,
                                   amount: 10, currency: "USD", recordedBy: bob, createdAt: Date())
        settlements.stored = [repayment]

        let vm = GroupViewModel(group: group, groupService: FakeGroupService(),
                                expenseService: expenses, settlementService: settlements,
                                currentUserIDProvider: { bob },
                                isConnectedProvider: { true })
        await vm.load(showError: false)   // online: populates vm.settlements
        #expect(!vm.settlements.isEmpty)
        #expect(!vm.balanceLoadFailed)
        // Stand in for the persistence a fuller fix would add (out of scope — see the report):
        // this is what lets the group's expenses survive into the offline reload below.
        CacheService.shared.saveExpenses([e], groupID: group.id)

        // Now the same group reloads offline in a view model that already carries the
        // settlements this session loaded online.
        let offlineVM = GroupViewModel(group: group, groupService: FakeGroupService(),
                                       expenseService: expenses, settlementService: settlements,
                                       currentUserIDProvider: { bob },
                                       isConnectedProvider: { false })
        offlineVM.settlements = vm.settlements
        await offlineVM.load(showError: false)

        #expect(!offlineVM.balanceLoadFailed)
        #expect(!offlineVM.settlementsMayBeStale)
    }

    // MARK: - Genuinely empty group

    @Test("A genuinely empty group offline shows neither the warning nor the error state")
    func genuinelyEmptyGroupOfflineShowsNothing() async {
        let group = makeGroup()
        let expenses = FakeExpenseService()
        let settlements = FakeSettlementService()

        let vm = GroupViewModel(group: group, groupService: FakeGroupService(),
                                expenseService: expenses, settlementService: settlements,
                                isConnectedProvider: { false })
        await vm.load(showError: false)

        #expect(!vm.balanceLoadFailed)
        #expect(vm.settlementSuggestions.isEmpty)
        #expect(!vm.settlementsMayBeStale)
        #expect(!vm.settleUpErrorStateShouldShow)
    }

    // MARK: - The pre-existing empty-list error state is unchanged

    @Test("The empty-list error state still appears when a load fails and there is nothing to show")
    func emptyListErrorStateStillAppears() async {
        // No other participant on the expense, so there is no debt and `settlementSuggestions`
        // is empty — the exact condition `settleUpErrorStateShouldShow` requires and
        // `settlementsMayBeStale` must not fire for.
        let group = makeGroup(); let alice = UUID()
        let expenses = FakeExpenseService(); let settlements = FakeSettlementService()
        let e = makeExpense(payerID: alice, groupID: group.id)
        expenses.expenses = [e]
        expenses.splits = []
        settlements.fetchError = AppError.networkUnavailable

        let vm = GroupViewModel(group: group, groupService: FakeGroupService(),
                                expenseService: expenses, settlementService: settlements,
                                currentUserIDProvider: { alice },
                                isConnectedProvider: { true })
        // Seed state as if this group was already known non-empty, matching how `load()`'s
        // catch branch restores from cache/prior state rather than the failed fetch.
        vm.expenses = [e]
        vm.hasKnownNonEmptyExpenses = true

        await vm.load(showError: false)

        #expect(vm.balanceLoadFailed)
        #expect(vm.settlementSuggestions.isEmpty)
        #expect(vm.settleUpErrorStateShouldShow)
        #expect(!vm.settlementsMayBeStale)
    }
}
