//
//  SplitEditorTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  SPLIT-01: adding a member who joined the group after an expense was created.
//
//  `SplitEditor.forEditing` builds the participant list for an existing expense. The rules it
//  encodes are the ones a naive implementation gets wrong, so each has a test.
//

import Testing
import Foundation
@testable import xBill

@Suite("Split editor — seeding an existing expense")
@MainActor
struct SplitEditorTests {

    private func user(_ name: String) -> User {
        User(id: UUID(), email: "\(name)@x.test", displayName: name,
             avatarURL: nil, createdAt: Date())
    }
    private func split(_ userID: UUID, _ amount: String) -> Split {
        Split(id: UUID(), expenseID: UUID(), userID: userID,
              amount: Decimal(string: amount)!, isSettled: false)
    }

    /// The original question: a member who joined later must be offered, unticked.
    @Test("A member not on the expense appears, unticked")
    func lateJoinerIsOfferedButNotIncluded() {
        let a = user("Alice"), b = user("Bob"), c = user("Carol")   // Carol joined later
        let editor = SplitEditor.forEditing(
            existingSplits: [split(a.id, "50"), split(b.id, "50")],
            members: [a, b, c], total: 100)

        #expect(editor.inputs.count == 3)
        #expect(editor.input(for: c.id)?.isIncluded == false)
        #expect(editor.includedInputs.count == 2)

        editor.toggle(participantID: c.id)
        #expect(editor.includedInputs.count == 3)
    }

    /// Someone who has left the group is still on the expense. Dropping them would rewrite history
    /// and silently move their debt onto everybody else.
    @Test("A departed member keeps their split and is not dropped")
    func departedMemberPreserved() {
        let a = user("Alice"), gone = UUID()
        let editor = SplitEditor.forEditing(
            existingSplits: [split(a.id, "40"), split(gone, "60")],
            members: [a], total: 100)

        #expect(editor.inputs.count == 2)
        let departed = editor.input(for: gone)
        #expect(departed?.isIncluded == true)
        #expect(departed?.amount == Decimal(60))
        #expect(departed?.displayName == "Former member")
    }

    /// The strategy is not persisted. Seeding `.equal` would assert something about the user's
    /// original intent that the data cannot support — and switching to it would immediately
    /// flatten an uneven split.
    @Test("Seeded as exact, preserving whatever the amounts already are")
    func seedsAsExact() {
        let a = user("A"), b = user("B")
        let editor = SplitEditor.forEditing(
            existingSplits: [split(a.id, "70"), split(b.id, "30")],
            members: [a, b], total: 100)
        #expect(editor.strategy == .exact)
        #expect(editor.input(for: a.id)?.amount == Decimal(70))
        #expect(editor.input(for: b.id)?.amount == Decimal(30))
    }

    /// Switching to equal is a deliberate act and must redistribute across the included set only.
    @Test("Switching to equal splits across included participants only")
    func equalUsesIncludedOnly() {
        let a = user("A"), b = user("B"), c = user("C")
        let editor = SplitEditor.forEditing(
            existingSplits: [split(a.id, "60"), split(b.id, "40")],
            members: [a, b, c], total: 100)
        editor.strategy = .equal
        editor.recompute()

        #expect(editor.includedInputs.count == 2)
        #expect(editor.input(for: a.id)?.amount == Decimal(50))
        #expect(editor.input(for: b.id)?.amount == Decimal(50))
        #expect(editor.input(for: c.id)?.isIncluded == false)
    }

    /// Removing someone must move their share onto the rest, not lose it.
    @Test("Removing a participant redistributes rather than losing the money")
    func removalRedistributes() {
        let a = user("A"), b = user("B")
        let editor = SplitEditor.forEditing(
            existingSplits: [split(a.id, "50"), split(b.id, "50")],
            members: [a, b], total: 100)
        editor.strategy = .equal
        editor.toggle(participantID: b.id)

        #expect(editor.includedInputs.count == 1)
        #expect(editor.input(for: a.id)?.amount == Decimal(100))
    }

    /// An id that is not present is a no-op, never a trap — CRASH-01's whole class.
    @Test("Editing an absent participant is inert")
    func absentParticipantIsInert() {
        let a = user("A")
        let editor = SplitEditor.forEditing(existingSplits: [split(a.id, "10")],
                                            members: [a], total: 10)
        let ghost = UUID()
        editor.toggle(participantID: ghost)
        editor.adjustShares(by: 3, participantID: ghost)
        editor.setAmount(99, participantID: ghost)
        #expect(editor.inputs.count == 1)
        #expect(editor.input(for: a.id)?.amount == Decimal(10))
    }

    @Test("Shares cannot drop below one")
    func sharesClampAtOne() {
        let a = user("A")
        let editor = SplitEditor.forEditing(existingSplits: [split(a.id, "10")],
                                            members: [a], total: 10)
        editor.adjustShares(by: -5, participantID: a.id)
        #expect(editor.input(for: a.id)?.shares == 1)
    }
}
