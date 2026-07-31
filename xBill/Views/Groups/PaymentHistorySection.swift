//
//  PaymentHistorySection.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

/// Recent payments, with attribution. Without this the ledger's two advantages over the old
/// boolean — knowing who recorded a payment, and being able to undo it — are invisible.
struct PaymentHistorySection: View {
    let settlements: [Settlement]
    let memberNames: [UUID: String]
    let currency: String
    let currentUserID: UUID?
    let onDelete: (Settlement) -> Void

    private func name(_ id: UUID) -> String { memberNames[id] ?? "Someone" }

    var body: some View {
        if !settlements.isEmpty {
            Section("Recent Payments") {
                ForEach(settlements) { settlement in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("\(name(settlement.fromUserID)) paid \(name(settlement.toUserID))")
                                .font(.appBody)
                            Spacer()
                            Text(settlement.amount.formatted(currencyCode: currency))
                                .font(.subheadline.monospacedDigit())
                        }
                        Text("recorded by \(name(settlement.recordedBy)) · \(settlement.createdAt.relativeFormatted)")
                            .font(.appCaption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .listRowBackground(Color.bgCard)
                    .accessibilityIdentifier("xBill.paymentHistory.row.\(settlement.id.uuidString)")
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // RLS permits deletion only by the recorder; showing it to anyone
                        // else would repeat the REV-01 mistake of offering an action the
                        // database will refuse.
                        if settlement.recordedBy == currentUserID {
                            Button(role: .destructive) { onDelete(settlement) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }
}
