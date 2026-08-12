//
//  SplitParticipantEditTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  CRASH-01 — the split participant row edits.
//
//  Shipped 1.0 (1) crashed on a real device with `Array._checkSubscript` → `_assertionFailure`,
//  reached from `Switch.updateUIView` through a `Binding` subscript getter. The Add Expense
//  participant list used `ForEach($vm.splitInputs)`, whose element bindings are backed by an
//  **array index**. UIKit reads those bindings back during a deferred update pass, after the body
//  that produced them has returned, and an index that no longer resolves traps.
//
//  ⚠️ These tests cannot reproduce that crash. The trap lives in SwiftUI's update cycle, needs a
//  real `UISwitch`, and the crash report carries no app frame below `main()`. What they *can* pin
//  is the property the view now depends on instead: **every participant edit resolves by `userID`
//  and is total** — a row that is not present is a no-op, never a trap. That is why the fix
//  routes through the view model rather than adding a bounds check at the call site: a call site
//  can forget, `firstIndex(where:) + guard` cannot.
//

import Testing
import Foundation
@testable import xBill

@Suite("Split participant edits resolve by id")
@MainActor
struct SplitParticipantEditTests {

    private let alice = UUID()
    private let bob = UUID()
    /// Never a member. Stands in for a row SwiftUI still holds after the roster changed.
    private let ghost = UUID()

    private func makeVM() -> AddExpenseViewModel {
        let group = BillGroup(id: UUID(), name: "Trip", emoji: "✈️", createdBy: alice,
                              isArchived: false, currency: "USD", createdAt: Date())
        let members = [
            User(id: alice, email: "a@b.com", displayName: "Alice", avatarURL: nil, createdAt: Date()),
            User(id: bob, email: "b@b.com", displayName: "Bob", avatarURL: nil, createdAt: Date())
        ]
        return AddExpenseViewModel(group: group, members: members, currentUserID: alice)
    }

    // MARK: - The crash property: unknown ids are inert

    @Test("Every edit for an absent participant is a no-op, not a trap")
    func absentParticipantIsInert() {
        let vm = makeVM()
        let before = vm.splitInputs

        vm.toggle(participantID: ghost)
        vm.setAmount(99, participantID: ghost)
        vm.adjustShares(by: 5, participantID: ghost)

        #expect(vm.splitInputs == before, "An absent participant must change nothing.")
        #expect(vm.input(for: ghost) == nil)
    }

    // MARK: - The other direction
    //
    // Without these, a view model whose every mutator did nothing at all would pass the test
    // above — which is exactly the shape of assertion this codebase has already been bitten by
    // (UIT-01: an assertion that could never fail still counted as covered).

    @Test("A known participant can still be toggled")
    func knownParticipantToggles() {
        let vm = makeVM()
        #expect(vm.input(for: bob)?.isIncluded == true)

        vm.toggle(participantID: bob)
        #expect(vm.input(for: bob)?.isIncluded == false)
        #expect(vm.input(for: alice)?.isIncluded == true, "Toggling one row must not touch another.")

        vm.toggle(participantID: bob)
        #expect(vm.input(for: bob)?.isIncluded == true)
    }

    @Test("A known participant's exact amount can still be set")
    func knownParticipantAmountIsSet() {
        let vm = makeVM()
        vm.splitStrategy = .exact
        vm.setAmount(Decimal(string: "12.34")!, participantID: bob)

        #expect(vm.input(for: bob)?.amount == Decimal(string: "12.34"))
        #expect(vm.input(for: alice)?.amount == .zero)
    }

    @Test("Shares adjust in both directions for a known participant")
    func knownParticipantSharesAdjust() {
        let vm = makeVM()
        vm.splitStrategy = .shares

        vm.adjustShares(by: 2, participantID: bob)
        #expect(vm.input(for: bob)?.shares == 3)

        vm.adjustShares(by: -1, participantID: bob)
        #expect(vm.input(for: bob)?.shares == 2)
    }

    /// The `-` button used to guard `shares > 1` at the call site. That rule now lives in the
    /// model, where a future caller cannot forget it — zero shares would make a shares split
    /// divide by zero weight.
    @Test("Shares clamp at one however far they are decremented")
    func sharesClampAtOne() {
        let vm = makeVM()
        vm.splitStrategy = .shares

        vm.adjustShares(by: -50, participantID: bob)
        #expect(vm.input(for: bob)?.shares == 1)
    }
}
