//
//  RecordPaymentSheet.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

/// Amount entry for a payment, pre-filled with the full outstanding figure.
///
/// The amount is free-form on purpose: a payment is an amount one person gave another, not a
/// selection of expense shares. That is what makes partial payment expressible and what
/// removed the partial-settlement failure mode (REV-02).
struct RecordPaymentSheet: View {
    let suggestion: SettlementSuggestion
    let currency: String
    let onConfirm: (Decimal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String

    init(suggestion: SettlementSuggestion, currency: String, onConfirm: @escaping (Decimal) -> Void) {
        self.suggestion = suggestion
        self.currency = currency
        self.onConfirm = onConfirm
        // `NSDecimalNumber.stringValue` drops trailing zeros, so an $8.00 debt prefilled as
        // "8" — the same trailing-zero behaviour that made PayPal.Me silently ignore a
        // settlement amount (`95USD` instead of `95.00USD`). `formattedAmount` is the house
        // fix: en_US_POSIX, exactly 2dp, grouping disabled — so it also cannot emit a comma
        // that `enteredAmount`'s parser would then reject.
        _amountText = State(initialValue: PaymentLinkService.formattedAmount(suggestion.amount))
    }

    private var enteredAmount: Decimal? {
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              value > .zero else { return nil }
        return value
    }

    private var exceedsOutstanding: Bool {
        guard let enteredAmount else { return false }
        return enteredAmount > suggestion.amount
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(suggestion.fromName) paid \(suggestion.toName)")
                        .font(.appBody)
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.xbillLargeAmount)
                        .accessibilityIdentifier("xBill.recordPayment.amountField")
                } footer: {
                    if exceedsOutstanding {
                        Text("More than the \(suggestion.amount.formatted(currencyCode: currency)) outstanding. This will leave \(suggestion.toName) owing the difference.")
                            .foregroundStyle(Color.moneyNegative)
                    }
                }
            }
            .navigationTitle("Record Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Record") {
                        if let enteredAmount { onConfirm(enteredAmount) }
                        dismiss()
                    }
                    .disabled(enteredAmount == nil)
                    .accessibilityIdentifier("xBill.recordPayment.confirmButton")
                }
            }
        }
    }
}
