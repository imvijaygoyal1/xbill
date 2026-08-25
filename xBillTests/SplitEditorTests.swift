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

// MARK: - SPLIT-05: percentage had no input anywhere in the app
//
// "By %" has been in the strategy picker since 1.0. Neither Add Expense nor the edit sheet ever
// rendered a percentage field, so every value stayed at 0, `validatePercentages` reported
// "Percentages must add up to 100. Currently: 0.00", and Save was disabled with no way out.
// A picker offering an option that cannot be completed is worse than not offering it.

@Suite("Percentage splits")
@MainActor
struct PercentageSplitTests {

    private func user(_ n: String) -> User {
        User(id: UUID(), email: "\(n)@x.test", displayName: n, avatarURL: nil, createdAt: Date())
    }
    private func split(_ id: UUID, _ amt: String) -> Split {
        Split(id: UUID(), expenseID: UUID(), userID: id,
              amount: Decimal(string: amt)!, isSettled: false)
    }

    /// The state a user is dropped into the moment they pick "By %".
    @Test("Percentages start invalid, which is why an input is required")
    func startsInvalid() {
        let a = user("A"), b = user("B")
        let e = SplitEditor.forEditing(existingSplits: [split(a.id, "50"), split(b.id, "50")],
                                       members: [a, b], total: 100)
        e.strategy = .percentage
        #expect(e.validationError != nil, "0% + 0% is not 100 — without a field the user is stuck")
    }

    @Test("Entering percentages divides the total and validates")
    func percentagesApply() {
        let a = user("A"), b = user("B")
        let e = SplitEditor.forEditing(existingSplits: [split(a.id, "50"), split(b.id, "50")],
                                       members: [a, b], total: 100)
        e.strategy = .percentage
        e.setPercentage(70, participantID: a.id)
        e.setPercentage(30, participantID: b.id)

        #expect(e.validationError == nil)
        #expect(e.input(for: a.id)?.amount == Decimal(70))
        #expect(e.input(for: b.id)?.amount == Decimal(30))
    }

    @Test("Percentages that do not reach 100 are rejected")
    func mustSumTo100() {
        let a = user("A"), b = user("B")
        let e = SplitEditor.forEditing(existingSplits: [split(a.id, "50"), split(b.id, "50")],
                                       members: [a, b], total: 100)
        e.strategy = .percentage
        e.setPercentage(40, participantID: a.id)
        e.setPercentage(30, participantID: b.id)
        #expect(e.validationError?.contains("70") == true)
    }

    /// Typing a leading minus must not produce a negative share.
    @Test("A negative percentage is clamped to zero")
    func negativeClamped() {
        let a = user("A")
        let e = SplitEditor.forEditing(existingSplits: [split(a.id, "10")], members: [a], total: 10)
        e.strategy = .percentage
        e.setPercentage(-25, participantID: a.id)
        #expect(e.input(for: a.id)?.percentage == 0)
    }

    /// Only included participants count toward the 100.
    @Test("An excluded participant does not consume percentage")
    func excludedIgnored() {
        let a = user("A"), b = user("B"), c = user("C")
        let e = SplitEditor.forEditing(existingSplits: [split(a.id, "50"), split(b.id, "50")],
                                       members: [a, b, c], total: 100)
        e.strategy = .percentage
        e.setPercentage(60, participantID: a.id)
        e.setPercentage(40, participantID: b.id)
        #expect(e.validationError == nil, "C is not included and must not be required to hold a %")
    }
}

// MARK: - Percentage progress hint
//
// "split by percentage works but input style is not very intuitive" — the only feedback was
// `validationError`, which reports a failure after the fact ("Currently: 65.00") rather than
// telling you what is left while you type.

@Suite("Percentage progress")
@MainActor
struct PercentageProgressTests {

    private func editor(_ n: Int) -> SplitEditor {
        let users = (0..<n).map { i in
            User(id: UUID(), email: "u\(i)@x.test", displayName: "U\(i)",
                 avatarURL: nil, createdAt: Date())
        }
        let splits = users.map {
            Split(id: UUID(), expenseID: UUID(), userID: $0.id, amount: 0, isSettled: false)
        }
        let e = SplitEditor.forEditing(existingSplits: splits, members: users, total: 100)
        e.strategy = .percentage
        return e
    }

    @Test("Starts with the whole amount unassigned")
    func startsAtOneHundred() {
        #expect(editor(2).percentageProgress?.remaining == 100)
    }

    @Test("Counts down as percentages are entered")
    func countsDown() {
        let e = editor(3)
        let ids = e.inputs.map(\.userID)
        e.setPercentage(40, participantID: ids[0])
        #expect(e.percentageProgress?.remaining == 60)
        e.setPercentage(35, participantID: ids[1])
        #expect(e.percentageProgress?.remaining == 25)
    }

    @Test("Reports completion at exactly 100")
    func completesAtHundred() {
        let e = editor(2)
        let ids = e.inputs.map(\.userID)
        e.setPercentage(70, participantID: ids[0])
        e.setPercentage(30, participantID: ids[1])
        let p = e.percentageProgress
        #expect(p?.isComplete == true)
        #expect(p?.isOver == false)
        #expect(e.validationError == nil)
    }

    /// Over-allocation must read differently from under-allocation, or the hint tells you to add
    /// more when you need to remove some.
    @Test("Over 100 is distinguishable from under")
    func overIsDistinct() {
        let e = editor(2)
        let ids = e.inputs.map(\.userID)
        e.setPercentage(80, participantID: ids[0])
        e.setPercentage(45, participantID: ids[1])
        let p = e.percentageProgress
        #expect(p?.isOver == true)
        #expect(p?.remaining == -25)
    }

    /// Excluding someone frees their share back up.
    @Test("Excluding a participant returns their percentage")
    func excludingFrees() {
        let e = editor(3)
        let ids = e.inputs.map(\.userID)
        e.setPercentage(50, participantID: ids[0])
        e.setPercentage(50, participantID: ids[1])
        #expect(e.percentageProgress?.isComplete == true)
        e.toggle(participantID: ids[1])
        #expect(e.percentageProgress?.remaining == 50)
    }

    @Test("No progress outside percentage mode")
    func nilOutsidePercentage() {
        let e = editor(2)
        e.strategy = .equal
        #expect(e.percentageProgress == nil)
    }
}
