//
//  SplitCalculatorReviewTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  Regression cover for the senior review of 2026-07-28 (REV-10 … REV-12).
//

import Foundation
import Testing
@testable import xBill

private func inputs(_ count: Int) -> [SplitInput] {
    (0..<count).map { SplitInput(userID: UUID(), displayName: "P\($0)") }
}

// MARK: - REV-10

@Suite("Percentage split validation")
struct PercentageSplitValidationTests {

    /// REV-10. `splitByPercentage` dumps the whole shortfall on one participant when the
    /// percentages do not sum to 100. Nothing validated that, and `canSave` only checked
    /// `.exact`, so a 40/30/20 split saved silently with 10% of the bill misallocated.
    @Test("Percentages that do not sum to 100 are rejected")
    func underSumIsRejected() {
        var split = inputs(3)
        split[0].percentage = 40
        split[1].percentage = 30
        split[2].percentage = 20

        let error = SplitCalculator.validatePercentages(inputs: split)

        #expect(error != nil)
        #expect(error?.contains("90") == true)
    }

    @Test("Percentages over 100 are rejected")
    func overSumIsRejected() {
        var split = inputs(2)
        split[0].percentage = 70
        split[1].percentage = 45

        #expect(SplitCalculator.validatePercentages(inputs: split) != nil)
    }

    @Test("Percentages summing to exactly 100 are accepted")
    func exactSumIsAccepted() {
        var split = inputs(3)
        split[0].percentage = 33.33
        split[1].percentage = 33.33
        split[2].percentage = 33.34

        #expect(SplitCalculator.validatePercentages(inputs: split) == nil)
    }

    @Test("Excluded participants do not count toward the total")
    func excludedAreIgnored() {
        var split = inputs(3)
        split[0].percentage = 50
        split[1].percentage = 50
        split[2].percentage = 25
        split[2].isIncluded = false

        #expect(SplitCalculator.validatePercentages(inputs: split) == nil)
    }
}

// MARK: - REV-11

@Suite("Settlement minimization rounding")
struct MinimizeTransactionsRoundingTests {

    /// REV-11. The transfer amount was emitted **rounded** but subtracted from the running
    /// balances **unrounded**, so sub-cent residuals survived and produced extra transfers.
    /// Here C owes 0.012 in total, which is one cent — but two separate 0.01 suggestions
    /// were emitted, asking C to pay double.
    @Test("Sub-cent residuals do not produce duplicate transfers")
    func subCentResidualDoesNotDuplicate() {
        let a = UUID(), b = UUID(), c = UUID()
        let balances: [UUID: Decimal] = [
            a: Decimal(string: "0.006")!,
            b: Decimal(string: "0.006")!,
            c: Decimal(string: "-0.012")!
        ]

        let suggestions = SplitCalculator.minimizeTransactions(
            balances: balances,
            names: [a: "A", b: "B", c: "C"],
            currency: "USD"
        )

        let total = suggestions.reduce(Decimal.zero) { $0 + $1.amount }
        #expect(total == Decimal(string: "0.01"))
        #expect(suggestions.count == 1)
    }

    @Test("A whole-cent settlement is unchanged")
    func wholeCentIsUnchanged() {
        let a = UUID(), b = UUID()
        let suggestions = SplitCalculator.minimizeTransactions(
            balances: [a: 25, b: -25],
            names: [a: "A", b: "B"],
            currency: "USD"
        )

        #expect(suggestions.count == 1)
        #expect(suggestions.first?.amount == 25)
        #expect(suggestions.first?.fromUserID == b)
        #expect(suggestions.first?.toUserID == a)
    }

    /// The loop must always make progress. A residual below half a cent emits nothing, so
    /// the balance has to be consumed by the unrounded amount or the loop spins forever.
    @Test("A residual below half a cent terminates without emitting")
    func subHalfCentTerminates() {
        let a = UUID(), b = UUID()
        let suggestions = SplitCalculator.minimizeTransactions(
            balances: [a: Decimal(string: "0.004")!, b: Decimal(string: "-0.004")!],
            names: [a: "A", b: "B"],
            currency: "USD"
        )

        #expect(suggestions.isEmpty)
    }
}

// MARK: - REV-12

@Suite("Split calculation with a zero total")
struct ZeroTotalSplitTests {

    /// REV-12. `splitEqually` computed `share / total * 100` with no zero guard. Decimal
    /// division by zero yields NaN, which would then be written into a split percentage.
    /// The only caller guards `total > 0`, so this was latent — but it is a public API.
    @Test("An equal split of zero produces zero amounts, not NaN")
    func equalSplitOfZero() {
        var split = inputs(3)

        SplitCalculator.splitEqually(total: .zero, inputs: &split)

        for entry in split {
            #expect(entry.amount == .zero)
            #expect(entry.percentage == .zero)
            #expect(!entry.percentage.isNaN)
        }
    }

    @Test("A shares split of zero produces zero amounts, not NaN")
    func sharesSplitOfZero() {
        var split = inputs(2)
        split[0].shares = 2

        SplitCalculator.splitByShares(total: .zero, inputs: &split)

        for entry in split {
            #expect(entry.amount == .zero)
            #expect(!entry.percentage.isNaN)
        }
    }

    @Test("A percentage split of zero produces zero amounts")
    func percentageSplitOfZero() {
        var split = inputs(2)
        split[0].percentage = 50
        split[1].percentage = 50

        SplitCalculator.splitByPercentage(total: .zero, inputs: &split)

        for entry in split {
            #expect(entry.amount == .zero)
        }
    }
}
