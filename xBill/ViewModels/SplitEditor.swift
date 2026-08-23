//
//  SplitEditor.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  The split half of an expense form: who is included, on what strategy, for how much.
//
//  Extracted from `AddExpenseViewModel` (SPLIT-01) so that **editing** an existing expense and
//  **creating** a new one share one implementation rather than two that must agree. This session
//  produced four defects (`INV-01`…`INV-04`) whose common cause was exactly that — two code paths
//  meant to behave identically, drifting. The split rules are too easy to get subtly wrong to
//  reimplement: the percentage validation exists because a 40/30/20 entry once saved silently with
//  the missing 10% dumped on one participant, and the shares clamp exists because the rule used to
//  live in a button and only held while every caller remembered it.
//
//  `AddExpenseViewModel` now owns one of these and forwards to it, so its public API is unchanged.
//

import Foundation
import Observation

@Observable
@MainActor
final class SplitEditor {

    var strategy: SplitStrategy = .equal
    var inputs: [SplitInput] = []

    /// The amount being divided. The owner sets this whenever its own total changes — for a new
    /// expense that is the (possibly converted) entered amount, for an edit the corrected one.
    var total: Decimal = .zero {
        didSet { if total != oldValue { recompute() } }
    }

    init(strategy: SplitStrategy = .equal, inputs: [SplitInput] = [], total: Decimal = .zero) {
        self.strategy = strategy
        self.inputs   = inputs
        self.total    = total
    }

    // MARK: - Validation

    /// Validation takes the total **explicitly** rather than reading the stored one.
    ///
    /// The stored `total` is only refreshed when the owner recomputes, so a caller that changes an
    /// amount and reads validation before recomputing would be validating against a stale figure.
    /// That regressed `exactSplitValidationControlsSave` the moment this type was extracted: the
    /// form reported "amounts must add up to 0.00" while showing a real amount. A pure function of
    /// (strategy, inputs, total) cannot go stale.
    func validationError(for total: Decimal) -> String? {
        switch strategy {
        case .exact:
            return SplitCalculator.validateExact(total: total, inputs: inputs)
        case .percentage:
            // REV-10: without this a 40/30/20 entry saved silently, with the missing 10% of the
            // bill dumped on one participant by the remainder assignment.
            return SplitCalculator.validatePercentages(inputs: inputs)
        case .equal, .shares:
            return nil
        }
    }

    /// Convenience for owners whose total is already this editor's own.
    var validationError: String? { validationError(for: total) }

    var includedInputs: [SplitInput] { inputs.filter(\.isIncluded) }

    // MARK: - Recompute

    func recompute() {
        guard total > .zero else {
            for i in inputs.indices { inputs[i].amount = .zero }
            return
        }
        switch strategy {
        case .equal:      SplitCalculator.splitEqually(total: total, inputs: &inputs)
        case .percentage: SplitCalculator.splitByPercentage(total: total, inputs: &inputs)
        case .shares:     SplitCalculator.splitByShares(total: total, inputs: &inputs)
        case .exact:      break
        }
    }

    // MARK: - Participant edits
    //
    // CRASH-01. Every mutation resolves its row **by id**, and a participant that is no longer
    // present is a no-op rather than a trap.
    //
    // The view once edited rows through `ForEach($vm.splitInputs)` element bindings, which are
    // backed by an **array index**. UIKit reads those from `Switch.updateUIView` during a deferred
    // update pass — after the body that produced them returned — and an index that no longer
    // resolves calls `Array._checkSubscript`, which traps. That shipped in 1.0 (1) and crashed on a
    // real device. `firstIndex(where:)` + `guard` cannot trap, so routing every edit through these
    // makes the whole class of failure unrepresentable rather than merely unlikely.

    func input(for participantID: UUID) -> SplitInput? {
        inputs.first { $0.userID == participantID }
    }

    func toggle(participantID: UUID) {
        guard let index = inputs.firstIndex(where: { $0.userID == participantID }) else { return }
        inputs[index].isIncluded.toggle()
        recompute()
    }

    func setAmount(_ amount: Decimal, participantID: UUID) {
        guard let index = inputs.firstIndex(where: { $0.userID == participantID }) else { return }
        inputs[index].amount = amount
    }

    /// Clamped at 1: a participant cannot hold zero shares, and the old `-` button enforced that at
    /// the call site — a rule that only held as long as every caller remembered it.
    func adjustShares(by delta: Int, participantID: UUID) {
        guard let index = inputs.firstIndex(where: { $0.userID == participantID }) else { return }
        inputs[index].shares = max(1, inputs[index].shares + delta)
        recompute()
    }

    // MARK: - Seeding an edit (SPLIT-01)

    /// Builds the participant list for an expense that already exists.
    ///
    /// Everyone currently on the expense is included, whether or not they are still an **active**
    /// group member: an expense may legitimately be split with someone who has since left, and
    /// silently dropping them would rewrite history and move their debt onto everyone else. Active
    /// members not yet on the expense appear unticked, which is what makes a late joiner
    /// addable — the original question behind SPLIT-01.
    ///
    /// The strategy is seeded as `.exact` because it is **not persisted**: `splits` stores amounts
    /// only. Presenting `.equal` would be a claim about the user's original intent that the data
    /// cannot support, and switching to it would immediately flatten a deliberate 70/30.
    static func forEditing(existingSplits: [Split],
                           members: [User],
                           total: Decimal) -> SplitEditor {
        let onExpense = Set(existingSplits.map(\.userID))
        var inputs: [SplitInput] = []

        for split in existingSplits {
            let member = members.first { $0.id == split.userID }
            var input = SplitInput(userID: split.userID,
                                   displayName: member?.displayName ?? "Former member",
                                   avatarURL: member?.avatarURL)
            input.amount     = split.amount
            input.isIncluded = true
            inputs.append(input)
        }
        for member in members where !onExpense.contains(member.id) {
            var input = SplitInput(userID: member.id,
                                   displayName: member.displayName,
                                   avatarURL: member.avatarURL)
            input.amount     = .zero
            input.isIncluded = false
            inputs.append(input)
        }
        return SplitEditor(strategy: .exact, inputs: inputs, total: total)
    }
}
