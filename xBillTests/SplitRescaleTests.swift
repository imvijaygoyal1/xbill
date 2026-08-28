//
//  SplitRescaleTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  SPLIT-02. Editing an expense's amount updated `expenses.amount` and left splits untouched, and
//  balances derive from splits — so a correction from £100 to £120 displayed £120 while everyone
//  still owed based on £100. It saved successfully and moved nothing.
//
//  Rescaling is PROPORTIONAL rather than an equal re-split, because the split strategy is not
//  persisted. `splits` stores amounts only; nothing records whether the user chose equal, exact,
//  percentage or shares. Re-splitting equally would silently destroy a deliberate 70/30, so the
//  ratio is preserved and the original intent survives whatever it was.
//

import Testing
import Foundation
@testable import xBill

@Suite("Split rescaling")
struct SplitRescaleTests {

    private func split(_ user: UUID, _ amount: String) -> Split {
        Split(id: UUID(), expenseID: UUID(), userID: user,
              amount: Decimal(string: amount)!)
    }
    private func sum(_ s: [Split]) -> Decimal { s.reduce(.zero) { $0 + $1.amount } }

    // MARK: - The headline behaviour

    @Test("An equal split stays equal")
    func equalStaysEqual() {
        let a = UUID(), b = UUID()
        let out = SplitCalculator.rescale(splits: [split(a, "50"), split(b, "50")],
                                          from: 100, to: 120, payerID: a)!
        #expect(out.map(\.amount) == [Decimal(60), Decimal(60)])
        #expect(sum(out) == 120)
    }

    /// The reason this is proportional and not an equal re-split.
    @Test("A deliberate 70/30 is preserved, not flattened")
    func unevenRatioPreserved() {
        let a = UUID(), b = UUID()
        let out = SplitCalculator.rescale(splits: [split(a, "70"), split(b, "30")],
                                          from: 100, to: 200, payerID: a)!
        #expect(out.map(\.amount) == [Decimal(140), Decimal(60)])
        #expect(sum(out) == 200)
    }

    @Test("Scaling down works the same way")
    func scalingDown() {
        let a = UUID(), b = UUID()
        let out = SplitCalculator.rescale(splits: [split(a, "80"), split(b, "20")],
                                          from: 100, to: 50, payerID: a)!
        #expect(out.map(\.amount) == [Decimal(40), Decimal(10)])
        #expect(sum(out) == 50)
    }

    // MARK: - Money must not leak

    /// The property that matters most: whatever the ratio, the parts sum to the whole. A penny
    /// lost here is a penny somebody is silently charged or forgiven.
    @Test("Rescaled splits always sum exactly to the new total")
    func alwaysSumsExactly() {
        let ids = (0..<3).map { _ in UUID() }
        for (from, to) in [("100", "121.37"), ("33.33", "99.99"), ("10", "0.03"), ("7.77", "12345.67")] {
            let original = [split(ids[0], "33.33"), split(ids[1], "33.33"), split(ids[2], "33.34")]
            let scaled = SplitCalculator.rescale(
                splits: original,
                from: Decimal(string: from)!, to: Decimal(string: to)!, payerID: ids[0])!
            #expect(sum(scaled) == Decimal(string: to)!,
                    "\(from) → \(to) summed to \(sum(scaled))")
        }
    }

    /// The remainder lands on the payer, who fronted the money — not spread invisibly.
    @Test("The rounding remainder goes to the payer")
    func remainderToPayer() {
        let a = UUID(), b = UUID(), c = UUID()
        let out = SplitCalculator.rescale(
            splits: [split(a, "10"), split(b, "10"), split(c, "10")],
            from: 30, to: 10, payerID: b)!
        #expect(sum(out) == 10)
        let payerShare = out.first { $0.userID == b }!.amount
        let others = out.filter { $0.userID != b }.map(\.amount)
        #expect(others.allSatisfy { $0 == Decimal(string: "3.33")! })
        #expect(payerShare == Decimal(string: "3.34")!)
    }

    // MARK: - Edges

    /// Editing anything other than the amount must not perturb a single penny.
    @Test("An unchanged total returns identical amounts")
    func unchangedTotalIsIdentity() {
        let a = UUID(), b = UUID()
        let original = [split(a, "63.41"), split(b, "36.59")]
        let out = SplitCalculator.rescale(splits: original, from: 100, to: 100, payerID: a)!
        #expect(out.map(\.amount) == original.map(\.amount))
    }

    /// A zero original total carries no ratio to preserve, so there is nothing to scale and the
    /// caller must decide. Returning nil makes that explicit rather than dividing by zero.
    @Test("A zero original total cannot be rescaled")
    func zeroOriginalIsUnscalable() {
        let a = UUID()
        #expect(SplitCalculator.rescale(splits: [split(a, "0")], from: 0, to: 50, payerID: a) == nil)
        #expect(SplitCalculator.rescale(splits: [], from: 100, to: 50, payerID: a) == nil)
    }

    /// NOTE the `Decimal(string:)`. Writing `to: 73.29` makes a Decimal through
    /// `ExpressibleByFloatLiteral`, which routes the value via `Double` and carries its error —
    /// the assertion then fails against a value that is right to the penny. The production path
    /// is safe (amounts are parsed from strings); this bit the test, and the fix is the same rule:
    /// money never travels through a float literal.
    @Test("A single participant absorbs the whole amount")
    func singleParticipant() {
        let a = UUID()
        let target = Decimal(string: "73.29")!
        let out = SplitCalculator.rescale(splits: [split(a, "100")], from: 100, to: target, payerID: a)!
        #expect(out.first?.amount == target)
    }
}
