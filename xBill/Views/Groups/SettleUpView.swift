//
//  SettleUpView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct SettleUpView: View {
    @Bindable var vm: GroupViewModel
    let currentUserID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var settlementToConfirm: SettlementSuggestion?
    @State private var isSettling = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.settlementSuggestions.isEmpty {
                    EmptyStateView(
                        icon: "checkmark.seal.fill",
                        title: "All Settled!",
                        message: "Everyone in \(vm.group.name) is square."
                    )
                } else {
                    suggestionList
                }
            }
            .navigationTitle("Settle Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Mark as Settled?",
                isPresented: Binding(
                    get: { settlementToConfirm != nil },
                    set: { if !$0 { settlementToConfirm = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Mark as Settled") {
                    guard let suggestion = settlementToConfirm, !isSettling else { return }
                    isSettling = true
                    settlementToConfirm = nil
                    Task {
                        await vm.recordSettlement(suggestion)
                        isSettling = false
                    }
                }
                .disabled(isSettling)
                Button("Cancel", role: .cancel) { settlementToConfirm = nil }
            } message: {
                if let s = settlementToConfirm {
                    Text("\(s.fromName) → \(s.toName): \(s.amount.formatted(currencyCode: s.currency)). This action cannot be undone.")
                }
            }
        }
        .errorAlert(item: $vm.errorAlert)
    }

    // MARK: - Suggestions

    private var suggestionList: some View {
        List(vm.settlementSuggestions) { suggestion in
            VStack(alignment: .leading, spacing: 12) {
                // Transfer arrow
                HStack(spacing: 8) {
                    Text(suggestion.fromName)
                        .font(.headline)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    Text(suggestion.toName)
                        .font(.headline)
                }

                // Amount — red when current user owes, green when owed to current user
                Text(suggestion.amount.formatted(currencyCode: suggestion.currency))
                    .font(.title2.bold())
                    .foregroundStyle(
                        suggestion.fromUserID == currentUserID
                            ? Color.moneyNegative
                            : Color.moneyPositive
                    )

                // Payment buttons
                HStack(spacing: 10) {
                    if let venmoURL = PaymentLinkService.shared.paymentLink(for: suggestion, method: .venmo) {
                        Link(destination: venmoURL) {
                            Label("Venmo", systemImage: "link")
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .liquidGlassButton(fallback: Color.blue.opacity(0.15), in: Capsule())
                        }
                    }

                    Button {
                        settlementToConfirm = suggestion
                    } label: {
                        Label("Mark Settled", systemImage: "checkmark")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .liquidGlassButton(fallback: Color.green.opacity(0.15), in: Capsule())
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

#Preview {
    SettleUpView(
        vm: GroupViewModel(group: BillGroup(
            id: UUID(), name: "Trip", emoji: "✈️",
            createdBy: UUID(), isArchived: false,
            currency: "USD", createdAt: Date()
        )),
        currentUserID: UUID()
    )
}
