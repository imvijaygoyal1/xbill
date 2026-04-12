import SwiftUI

struct ReceiptReviewView: View {
    @Bindable var vm: ReceiptViewModel
    let onConfirmed: ([SplitInput]) -> Void

    @State private var showAddItem  = false
    @State private var newItemName  = ""
    @State private var newItemPrice = ""

    var body: some View {
        List {
            // Parsing tier + confidence header
            confidenceHeader

            // Validation warning (math mismatch)
            if let warning = vm.validationWarning {
                Section {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            // Merchant
            if let merchant = vm.scannedReceipt?.merchant {
                Section {
                    Label(merchant, systemImage: "storefront.fill")
                        .font(.headline)
                }
            }

            // Items
            Section("Items") {
                ForEach($vm.items) { $item in
                    itemRow(item: $item)
                }
                .onDelete { vm.items.remove(atOffsets: $0) }

                Button { showAddItem = true } label: {
                    Label("Add Item", systemImage: "plus")
                }
            }

            // Tax / Tip / Total
            Section("Extras") {
                if let tax = vm.scannedReceipt?.tax {
                    HStack {
                        Text("Tax")
                        Spacer()
                        Text(tax.formatted(currencyCode: "USD")).foregroundStyle(.secondary)
                    }
                }
                if let tip = vm.scannedReceipt?.tip {
                    HStack {
                        Text("Tip")
                        Spacer()
                        Text(tip.formatted(currencyCode: "USD")).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("Grand Total").bold()
                    Spacer()
                    Text(vm.grandTotal.formatted(currencyCode: "USD")).bold()
                }
            }

            // Per-person totals
            if !vm.members.isEmpty {
                Section("Per Person") {
                    ForEach(vm.members) { member in
                        HStack {
                            AvatarView(name: member.displayName, url: member.avatarURL, size: 28)
                            Text(member.displayName)
                            Spacer()
                            Text(vm.total(for: member.id).formatted(currencyCode: "USD"))
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
                Button("Use These Splits") {
                    onConfirmed(vm.asSplitInputs())
                }
                .fontWeight(.semibold)
            }
        }
        .alert("Add Item", isPresented: $showAddItem) {
            TextField("Name", text: $newItemName)
            TextField("Price", text: $newItemPrice).keyboardType(.decimalPad)
            Button("Add") {
                if let price = Decimal(string: newItemPrice), price > .zero {
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
                // Tier label
                Label(vm.parsingTier.isEmpty ? "Scanned" : vm.parsingTier,
                      systemImage: vm.parsingTier == "Apple Intelligence" ? "apple.logo" : "text.magnifyingglass")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()

                // Confidence badge
                Text(vm.confidenceLabel)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(confidenceColor.opacity(0.15))
                    .foregroundStyle(confidenceColor)
                    .clipShape(Capsule())
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

    // MARK: - Item Row

    @ViewBuilder
    private func itemRow(item: Binding<ReceiptItem>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Item name", text: item.name)
                    .font(.subheadline)
                Spacer()
                Text(item.wrappedValue.totalPrice.formatted(currencyCode: "USD"))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Quantity stepper
            HStack(spacing: 12) {
                Text("Qty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper(
                    value: Binding(
                        get: { item.wrappedValue.quantity },
                        set: { vm.updateQuantity(itemID: item.wrappedValue.id, quantity: $0) }
                    ),
                    in: 1...99
                ) {
                    Text("\(item.wrappedValue.quantity)")
                        .font(.caption.monospacedDigit())
                        .frame(minWidth: 24)
                }
                .fixedSize()

                Text("@ \(item.wrappedValue.unitPrice.formatted(currencyCode: "USD")) each")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            // Member assignment chips
            if !vm.members.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(vm.members) { member in
                            let assigned = item.wrappedValue.assignedUserIDs.contains(member.id)
                            Button {
                                vm.assign(userID: member.id, to: item.wrappedValue.id)
                            } label: {
                                Text(member.displayName.components(separatedBy: " ").first
                                     ?? member.displayName)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(assigned ? Color.accentColor : Color(.systemGray5))
                                    .foregroundStyle(assigned ? .white : .primary)
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
