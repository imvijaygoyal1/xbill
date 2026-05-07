//
//  SplitCalculator.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation

// MARK: - SplitCalculator

/// Pure, @Sendable-safe split logic. All methods are static — no shared state.
enum SplitCalculator {

    // MARK: - Equal Split

    /// Divides `total` equally among all `inputs` that are included.
    /// Handles rounding remainder by adding 1 cent to the first participant.
    static func splitEqually(total: Decimal, inputs: inout [SplitInput]) {
        let included = inputs.indices.filter { inputs[$0].isIncluded }
        guard !included.isEmpty else { return }

        let count = Decimal(included.count)
        var base = total / count
        var rounded = Decimal()
        NSDecimalRound(&rounded, &base, 2, .bankers)

        let distributed = rounded * count
        var remainder = total - distributed

        for (offset, index) in included.enumerated() {
            var share = rounded
            if offset == 0 {
                share += remainder
                remainder = .zero
            }
            inputs[index].amount = share
            inputs[index].percentage = (share / total * 100).rounded
        }
    }

    // MARK: - Percentage Split

    /// Distributes `total` proportionally to each input's `percentage`.
    /// Adjusts the first participant to absorb rounding error.
    static func splitByPercentage(total: Decimal, inputs: inout [SplitInput]) {
        let included = inputs.indices.filter { inputs[$0].isIncluded }
        guard !included.isEmpty else { return }

        var distributed = Decimal.zero
        for index in included {
            var amount = total * (inputs[index].percentage / 100)
            var rounded = Decimal()
            NSDecimalRound(&rounded, &amount, 2, .bankers)
            inputs[index].amount = rounded
            distributed += rounded
        }

        // Assign remainder to first included participant
        if let first = included.first {
            inputs[first].amount += total - distributed
        }
    }

    // MARK: - Shares Split

    /// Distributes `total` proportionally to each input's `shares` value.
    /// Adjusts the first included participant to absorb rounding error.
    static func splitByShares(total: Decimal, inputs: inout [SplitInput]) {
        let included = inputs.indices.filter { inputs[$0].isIncluded }
        guard !included.isEmpty else { return }

        let totalShares = included.reduce(0) { $0 + inputs[$1].shares }
        guard totalShares > 0 else { return }

        let totalSharesDecimal = Decimal(totalShares)
        var distributed = Decimal.zero

        for index in included {
            let shareCount = Decimal(inputs[index].shares)
            var amount = total * shareCount / totalSharesDecimal
            var rounded = Decimal()
            NSDecimalRound(&rounded, &amount, 2, .bankers)
            inputs[index].amount = rounded
            inputs[index].percentage = (shareCount / totalSharesDecimal * 100).rounded
            distributed += rounded
        }

        // Assign remainder to first included participant
        if let first = included.first {
            inputs[first].amount += total - distributed
        }
    }

    // MARK: - Exact Split (validate totals)

    /// Returns an error string if exact amounts don't sum to total, nil otherwise.
    static func validateExact(total: Decimal, inputs: [SplitInput]) -> String? {
        let sum = inputs.filter(\.isIncluded).reduce(Decimal.zero) { $0 + $1.amount }
        var diff = total - sum
        var absDiff = Decimal()
        NSDecimalRound(&absDiff, &diff, 2, .bankers)
        if absDiff != .zero {
            return "Amounts must add up to \(total). Remaining: \(absDiff)"
        }
        return nil
    }

    // MARK: - Settlement Suggestions (debt simplification)

    /// Given net balances (positive = owed, negative = owes),
    /// produces the minimum number of transfers to settle all debts.
    static func minimizeTransactions(
        balances: [UUID: Decimal],
        names: [UUID: String],
        currency: String
    ) -> [SettlementSuggestion] {
        var creditors = balances.filter { $0.value > .zero }.map { ($0.key, $0.value) }
            .sorted { $0.1 > $1.1 }
        var debtors = balances.filter { $0.value < .zero }.map { ($0.key, $0.value) }
            .sorted { $0.1 < $1.1 }

        var suggestions: [SettlementSuggestion] = []

        var ci = 0
        var di = 0
        while ci < creditors.count && di < debtors.count {
            let (creditorID, credit) = creditors[ci]
            let (debtorID, debt)     = debtors[di]

            let transferAmount = min(credit, -debt)
            suggestions.append(SettlementSuggestion(
                id: UUID(),
                fromUserID: debtorID,
                fromName: names[debtorID] ?? "Unknown",
                toUserID: creditorID,
                toName: names[creditorID] ?? "Unknown",
                amount: transferAmount,
                currency: currency
            ))

            creditors[ci] = (creditorID, credit - transferAmount)
            debtors[di]   = (debtorID, debt + transferAmount)

            if creditors[ci].1 == .zero { ci += 1 }
            if debtors[di].1  == .zero { di += 1 }
        }

        return suggestions
    }

    // MARK: - Net Balances

    /// Computes each member's net balance across a list of expenses and their splits.
    /// Positive = is owed money. Negative = owes money.
    ///
    /// Algorithm: for each unsettled, non-payer split, credit the payer and debit
    /// the participant. Settled splits are skipped entirely (debt already repaid).
    /// The payer's own split is also skipped — they already paid their own share.
    static func netBalances(
        expenses: [Expense],
        splits: [UUID: [Split]]   // keyed by expense ID
    ) -> [UUID: Decimal] {
        var balances: [UUID: Decimal] = [:]

        for expense in expenses {
            guard let payerID = expense.payerID else { continue }
            for split in splits[expense.id] ?? [] {
                // Skip payer's own split and already-settled debts
                guard !split.isSettled, split.userID != payerID else { continue }

                var amount = split.amount
                var rounded = Decimal()
                NSDecimalRound(&rounded, &amount, 2, .bankers)

                balances[payerID, default: .zero]      += rounded
                balances[split.userID, default: .zero] -= rounded
            }
        }

        return balances
    }
}
