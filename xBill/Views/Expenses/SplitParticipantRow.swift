//
//  SplitParticipantRow.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  One participant line in a split, with the input its strategy actually needs.
//
//  SPLIT-05. "By %" has been offered in the strategy picker since 1.0 and **there has never been a
//  percentage input anywhere in the app** — not in Add Expense, not in the edit sheet I added.
//  Selecting it leaves every percentage at 0, `validatePercentages` reports "Percentages must add
//  up to 100. Currently: 0.00", and Save stays disabled forever with no way out. A picker offering
//  four options, one of which cannot be completed, is worse than three options.
//
//  Shared by the create form and the edit sheet deliberately: two copies of this row is how the
//  edit sheet came to be missing three of the four inputs in the first place.
//

import SwiftUI

struct SplitParticipantRow: View {
    let input: SplitInput
    let strategy: SplitStrategy
    let currency: String
    /// Shown under the name when the person is no longer in the group. An expense may legitimately
    /// be split with someone who has left, and they must stay visible rather than silently vanish.
    var subtitle: String? = nil
    /// Prefix for accessibility identifiers, so the two forms stay individually addressable.
    ///
    /// ⚠️ The suffixes below (`includeToggle`, `exactAmountField`, `decreaseShares`,
    /// `increaseShares`) are the names `AddExpenseView` shipped and `RegressionUITests` matches on.
    /// Extracting this row initially renamed them, and `testSplitModeControlsRegression` failed —
    /// an accessibility identifier is a **contract with the test suite**, not an implementation
    /// detail. Do not rename one without updating every predicate that matches it.
    var idPrefix: String

    let onToggle: () -> Void
    let onAmount: (Decimal) -> Void
    let onPercentage: (Decimal) -> Void
    let onShares: (Int) -> Void

    var body: some View {
        HStack(spacing: XBillSpacing.sm) {
            Toggle(isOn: Binding(get: { input.isIncluded }, set: { _ in onToggle() })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(input.displayName)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityIdentifier("\(idPrefix).includeToggle.\(input.userID.uuidString)")

            if input.isIncluded { trailingControl }
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch strategy {
        case .exact:
            TextField("0.00", value: Binding(get: { input.amount }, set: onAmount),
                      format: .number.precision(.fractionLength(2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 88)
                .accessibilityIdentifier("\(idPrefix).exactAmountField.\(input.userID.uuidString)")

        case .percentage:
            HStack(spacing: 2) {
                TextField("0", value: Binding(get: { input.percentage }, set: onPercentage),
                          format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                    .accessibilityIdentifier("\(idPrefix).percentField.\(input.userID.uuidString)")
                Text("%").foregroundStyle(.secondary)
            }

        case .shares:
            HStack(spacing: XBillSpacing.xs) {
                Button { onShares(-1) } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(input.shares > 1 ? Color.brandPrimary : Color.textTertiary)
                }
                .buttonStyle(.plain)
                .contentShape(Circle())          // TAP-01: the glyph is not the hit region
                .disabled(input.shares <= 1)
                .accessibilityIdentifier("\(idPrefix).decreaseShares.\(input.userID.uuidString)")

                Text("\(input.shares)×").monospacedDigit().frame(minWidth: 28)

                Button { onShares(1) } label: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(Color.brandPrimary)
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .accessibilityIdentifier("\(idPrefix).increaseShares.\(input.userID.uuidString)")
            }

        case .equal:
            Text(input.amount.formatted(currencyCode: currency))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
