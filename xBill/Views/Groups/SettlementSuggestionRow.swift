//
//  SettlementSuggestionRow.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  Extracted from `GroupDetailView`, which was 1,197 lines across five types and had already been
//  split into three computed properties to escape a Swift type-checker timeout.
//
//  This row carries a lot of hard-won behaviour: it names the parties in text (a settlement once
//  read "A → A $7.00" whenever two members shared an initial), gates Record Payment on
//  `isParty` to match migration 041's INSERT policy exactly, explains itself when the user is
//  not a party, and keeps its accessibility identifier on the header rather than the container —
//  the container-level identifier was overwriting every child's (UIT-01).
//
//  The payment handoff state machine deliberately stays in `GroupDetailView`: it has two
//  device-only defects behind it and is driven by view state that has no meaning outside that
//  screen. This view reports the intent and lets the owner decide.
//

import SwiftUI

struct SettlementSuggestionRow: View {
    let suggestion: SettlementSuggestion
    let currentUserID: UUID
    let members: [User]
    let onRecordPayment: (SettlementSuggestion) -> Void
    let onOpenPayment: (URL, String, SettlementSuggestion) -> Void

    var body: some View {
        let isParty = currentUserID == suggestion.fromUserID || currentUserID == suggestion.toUserID
        return VStack(spacing: XBillSpacing.md) {
            // Two avatars and an amount used to be the whole row, so a settlement read as
            // "A → A $7.00" whenever two members shared an initial — which is exactly when
            // knowing who owes whom matters most. Name the parties in text.
            let debtorIsMe   = currentUserID == suggestion.fromUserID
            let debtorLabel  = debtorIsMe ? "You" : suggestion.fromName
            let creditorLabel = currentUserID == suggestion.toUserID ? "you" : suggestion.toName

            HStack(spacing: XBillSpacing.md) {
                AvatarView(name: suggestion.fromName, size: XBillIcon.avatarSm)
                VStack(alignment: .leading, spacing: 2) {
                    Text(debtorLabel)
                        .font(.appBody)
                        .foregroundStyle(Color.textPrimary)
                    Text("\(debtorIsMe ? "owe" : "owes") \(creditorLabel)")
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                }
                .lineLimit(1)
                Spacer(minLength: XBillSpacing.sm)
                Text(suggestion.amount.formatted(currencyCode: suggestion.currency))
                    .font(.xbillLargeAmount)
                    .foregroundStyle(Color.textPrimary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(suggestion.fromName) owes \(suggestion.toName) \(suggestion.amount.formatted(currencyCode: suggestion.currency))")
            // The row identifier belongs HERE, on the header — which already forms its own
            // accessibility element — not on the enclosing VStack. Applied to the container it
            // propagates to every descendant and *overwrites* their own identifiers, so
            // `recordPaymentButton`, `venmoButton`, `paypalButton`, `noPaymentHandle` and
            // `nonPartyCaption` did not exist at runtime: every element in the row reported the
            // row id. The regression suite's `xBill.settleUp.recordPaymentButton.` predicate
            // could therefore never match; it survived only inside `||` chains where another
            // branch was true. Found by the element dump in `testSettleUpLedgerRegression`.
            .accessibilityIdentifier("xBill.settleUp.suggestionRow.\(suggestion.id)")
            if isParty {
                XBillButton(title: "Record Payment", style: .primary) {
                    onRecordPayment(suggestion)
                }
                .accessibilityIdentifier("xBill.settleUp.recordPaymentButton.\(suggestion.id)")
            } else {
                // A dimmed row with no button and no explanation reads as a bug. Migration 041's
                // INSERT policy requires `auth.uid() IN (from_user_id, to_user_id)`, so this is a
                // real constraint rather than a UI choice — say so, matching the neighbouring
                // "Ask <name> to add a payment handle" pattern rather than leaving it silent.
                Text("Only \(suggestion.fromName) or \(suggestion.toName) can record this payment.")
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("xBill.settleUp.nonPartyCaption.\(suggestion.id)")
            }
            if currentUserID == suggestion.fromUserID,
               let recipient = members.first(where: { $0.id == suggestion.toUserID }) {
                let venmoHandle  = PaymentHandleValidator.normalized(recipient.venmoHandle, for: .venmo)
                let paypalHandle = PaymentHandleValidator.normalized(recipient.paypalHandle, for: .paypal)

                if venmoHandle == nil && paypalHandle == nil {
                    // Previously this rendered nothing at all, so the absence of a payment
                    // button looked like a bug rather than missing recipient data.
                    Text("Ask \(suggestion.toName) to add a payment handle in their profile.")
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("xBill.settleUp.noPaymentHandle.\(suggestion.id)")
                } else {
                    HStack(spacing: AppSpacing.sm) {
                        if let handle = venmoHandle,
                           let venmoURL = PaymentLinkService.shared.paymentLink(for: suggestion, recipient: recipient, method: .venmo) {
                            Button {
                                onOpenPayment(venmoURL, "Venmo", suggestion)
                            } label: {
                                Label("Venmo · @\(handle)", systemImage: "link")
                                    .font(.appCaptionMedium)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("xBill.settleUp.venmoButton.\(suggestion.id)")
                        }
                        if let handle = paypalHandle,
                           let paypalURL = PaymentLinkService.shared.paymentLink(for: suggestion, recipient: recipient, method: .paypal) {
                            Button {
                                onOpenPayment(paypalURL, "PayPal", suggestion)
                            } label: {
                                Label("PayPal · @\(handle)", systemImage: "link")
                                    .font(.appCaptionMedium)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("xBill.settleUp.paypalButton.\(suggestion.id)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, XBillSpacing.sm)
        .opacity(isParty ? 1 : 0.55)
    }
}
