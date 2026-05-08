//
//  ReceiptReviewView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct ReceiptReviewView: View {
    @Bindable var vm: ReceiptViewModel
    let onConfirmed: ([SplitInput]) -> Void

    @State private var showAddItem  = false
    @State private var newItemName  = ""
    @State private var newItemPrice = ""

    private var currency: String { vm.scannedReceipt?.currency ?? "USD" }

    var body: some View {
        List {
            confidenceHeader

            if let warning = vm.validationWarning {
                Section {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            if vm.hasUnassignedItems {
                Section {
                    Label("Some items have no one assigned — tap member chips below each item.",
                          systemImage: "person.fill.questionmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MERCHANT")
                        .font(.xbillUpperLabel)
                        .tracking(1.08)
                        .foregroundStyle(Color.textTertiary)
                    XBillTextField(
                        placeholder: "Merchant name",
                        text: $vm.merchantName
                    )
                }
            }

            Section("Items") {
                ForEach($vm.items) { $item in
                    ItemRow(item: $item, vm: vm, currency: currency)
                }
                .onDelete { vm.items.remove(atOffsets: $0) }

                Button { showAddItem = true } label: {
                    Label("Add Item", systemImage: "plus")
                }
            }

            Section("Extras") {
                // Gap 4: Transaction date extracted by NSDataDetector from OCR text
                if let txDate = vm.scannedReceipt?.transactionDate {
                    LabeledContent("Receipt Date") {
                        Text(txDate, style: .date).foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Receipt date: \(txDate.formatted(date: .long, time: .omitted))")
                }

                if let tax = vm.scannedReceipt?.tax {
                    LabeledContent("Tax") {
                        Text(tax.formatted(currencyCode: currency)).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("TIP")
                        .font(.xbillUpperLabel)
                        .tracking(1.08)
                        .foregroundStyle(Color.textTertiary)
                    XBillTextField(
                        placeholder: "0.00 (optional)",
                        text: $vm.tipAmount,
                        keyboardType: .decimalPad
                    )
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("TOTAL AMOUNT")
                        .font(.xbillUpperLabel)
                        .tracking(1.08)
                        .foregroundStyle(Color.textTertiary)
                    XBillTextField(
                        placeholder: "0.00",
                        text: $vm.totalAmount,
                        keyboardType: .decimalPad
                    )
                }
            }

            if !vm.members.isEmpty {
                Section("Per Person") {
                    ForEach(vm.members) { member in
                        HStack {
                            AvatarView(name: member.displayName, url: member.avatarURL, size: 28)
                            Text(member.displayName)
                            Spacer()
                            Text(vm.total(for: member.id).formatted(currencyCode: currency))
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationTitle("Review Receipt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Use These Splits") { onConfirmed(vm.asSplitInputs()) }
                    .fontWeight(.semibold)
            }
        }
        .alert("Add Item", isPresented: $showAddItem) {
            TextField("Name", text: $newItemName)
            TextField("Price", text: $newItemPrice).keyboardType(.decimalPad)
            Button("Add") {
                let normalized = newItemPrice.replacingOccurrences(of: ",", with: ".")
                if let price = Decimal(string: normalized), price > .zero {
                    vm.addItem(name: newItemName, unitPrice: price)
                }
                newItemName = ""; newItemPrice = ""
            }
            Button("Cancel", role: .cancel) { newItemName = ""; newItemPrice = "" }
        }
    }

    // MARK: - Confidence Header

    private var confidenceHeader: some View {
        Section {
            HStack(spacing: 10) {
                Label(vm.parsingTier.isEmpty ? "Scanned" : vm.parsingTier,
                      systemImage: vm.parsingTier == "Apple Intelligence" ? "apple.logo" : "text.magnifyingglass")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(vm.confidenceLabel)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(confidenceColor.opacity(0.15))
                    .foregroundStyle(confidenceColor)
                    .clipShape(Capsule())
            }

            // Suggested category chip (Gap 5: auto-category from merchant/items)
            if let category = vm.suggestedCategory {
                HStack(spacing: 6) {
                    Image(systemName: category.systemImage)
                        .font(.caption)
                    Text("Suggested: \(category.displayName)")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel("Suggested category: \(category.displayName)")
            }
        }
    }

    private var confidenceColor: Color {
        switch vm.confidence {
        case 0.90...: return .green
        case 0.75...: return .orange
        default:      return .red
        }
    }
}

// MARK: - ItemRow
// File-private subview so it can hold @State for the price text field.

private struct ItemRow: View {
    @Binding var item: ReceiptItem
    @Bindable var vm:  ReceiptViewModel
    let currency:      String

    @State private var priceText: String = ""

    var isAllAssigned: Bool {
        !vm.members.isEmpty && vm.members.allSatisfy { item.assignedUserIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Item name", text: $item.name)
                    .font(.subheadline)
                Spacer(minLength: 8)
                // Inline price editing
                TextField("0.00", text: $priceText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                    .onAppear { priceText = "\(item.unitPrice)" }
                    .onChange(of: priceText) { _, text in
                        let normalized = text.replacingOccurrences(of: ",", with: ".")
                        if let price = Decimal(string: normalized), price > .zero {
                            vm.updateUnitPrice(itemID: item.id, unitPrice: price)
                        }
                    }
                    .onChange(of: item.unitPrice) { _, newPrice in
                        priceText = "\(newPrice)"
                    }
            }

            // Quantity stepper
            HStack(spacing: 12) {
                Text("Qty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper(
                    value: Binding(
                        get: { item.quantity },
                        set: { vm.updateQuantity(itemID: item.id, quantity: $0) }
                    ),
                    in: 1...99
                ) {
                    Text("\(item.quantity)")
                        .font(.caption.monospacedDigit())
                        .frame(minWidth: 24)
                }
                .fixedSize()
                Text("@ \(item.unitPrice.formatted(currencyCode: currency)) each")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // Member assignment chips with "All" shortcut
            if !vm.members.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        // "All" chip — assigns/unassigns everyone at once
                        Button {
                            vm.toggleAssignAll(to: item.id)
                        } label: {
                            Text("All")
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(isAllAssigned ? Color.brandPrimary : Color(.systemGray5))
                                .foregroundStyle(isAllAssigned ? Color.white : Color.primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        ForEach(vm.members) { member in
                            let assigned = item.assignedUserIDs.contains(member.id)
                            Button {
                                vm.assign(userID: member.id, to: item.id)
                            } label: {
                                Text(member.displayName.components(separatedBy: " ").first ?? member.displayName)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(assigned ? Color.accentColor : Color(.systemGray5))
                                    .foregroundStyle(assigned ? Color.white : Color.primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        ReceiptReviewView(vm: ReceiptViewModel()) { _ in }
    }
}
