import SwiftUI

struct AddExpenseView: View {
    let group: BillGroup
    let members: [User]
    let currentUserID: UUID
    let onSaved: () async -> Void

    @State private var vm: AddExpenseViewModel
    @State private var showReceiptScan = false
    @State private var receiptVM = ReceiptViewModel()
    @Environment(\.dismiss) private var dismiss

    init(group: BillGroup, members: [User], currentUserID: UUID, onSaved: @escaping () async -> Void) {
        self.group         = group
        self.members       = members
        self.currentUserID = currentUserID
        self.onSaved       = onSaved
        _vm = State(initialValue: AddExpenseViewModel(group: group, members: members, currentUserID: currentUserID))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgSecondary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: XBillSpacing.xl) {

                        // MARK: Amount hero
                        VStack(spacing: XBillSpacing.xs) {
                            HStack(alignment: .firstTextBaseline, spacing: XBillSpacing.xs) {
                                // Currency badge — tap to change
                                Menu {
                                    ForEach(ExchangeRateService.commonCurrencies, id: \.self) { code in
                                        Button(code) {
                                            vm.expenseCurrency = code
                                            Task { await vm.updateConversion() }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 2) {
                                        Text(vm.expenseCurrency)
                                            .font(.xbillLargeAmount)
                                            .foregroundStyle(vm.isForeignCurrency
                                                             ? Color.brandPrimary
                                                             : Color.textTertiary)
                                        Image(systemName: "chevron.down")
                                            .font(.caption2.bold())
                                            .foregroundStyle(vm.isForeignCurrency
                                                             ? Color.brandPrimary
                                                             : Color.textTertiary)
                                    }
                                }
                                TextField("0.00", text: $vm.amountText)
                                    .font(.xbillHeroAmount)
                                    .multilineTextAlignment(.center)
                                    .keyboardType(.decimalPad)
                                    .foregroundStyle(Color.textPrimary)
                                    .onChange(of: vm.amountText) { _, _ in
                                        Task { await vm.updateConversion() }
                                    }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, XBillSpacing.base)
                            Rectangle()
                                .frame(height: 1)
                                .foregroundStyle(Color.inputBorder)

                            // Conversion preview
                            if vm.isForeignCurrency {
                                conversionPreview
                            }
                        }
                        .padding(.horizontal, XBillSpacing.xl)

                        // MARK: Expense section
                        VStack(alignment: .leading, spacing: XBillSpacing.sm) {
                            sectionHeader("Expense")
                            XBillTextField(placeholder: "What was it for?", text: $vm.title)
                                .padding(.horizontal, XBillSpacing.base)
                        }

                        // MARK: Category chips
                        VStack(alignment: .leading, spacing: XBillSpacing.sm) {
                            sectionHeader("Category")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: XBillSpacing.sm) {
                                    ForEach(Expense.Category.allCases, id: \.self) { cat in
                                        CategoryChipView(category: cat, isSelected: vm.category == cat) {
                                            vm.category = cat
                                            HapticManager.selection()
                                        }
                                    }
                                }
                                .padding(.horizontal, XBillSpacing.base)
                            }
                        }

                        // MARK: Paid by
                        VStack(alignment: .leading, spacing: XBillSpacing.sm) {
                            sectionHeader("Paid By")
                            XBillCard {
                                Picker("Paid by", selection: $vm.payerID) {
                                    ForEach(members) { member in
                                        HStack {
                                            AvatarView(name: member.displayName, url: member.avatarURL, size: XBillIcon.avatarSm)
                                            Text(member.displayName)
                                        }
                                        .tag(Optional(member.id))
                                    }
                                }
                                .tint(Color.brandPrimary)
                            }
                            .padding(.horizontal, XBillSpacing.base)
                        }

                        // MARK: Notes
                        VStack(alignment: .leading, spacing: XBillSpacing.sm) {
                            sectionHeader("Notes (optional)")
                            XBillCard {
                                TextField("Add a note…", text: $vm.notes, axis: .vertical)
                                    .font(.xbillBodyLarge)
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(2...4)
                            }
                            .padding(.horizontal, XBillSpacing.base)
                        }

                        // MARK: Split strategy
                        VStack(alignment: .leading, spacing: XBillSpacing.sm) {
                            sectionHeader("How to Split")
                            XBillCard {
                                Picker("Strategy", selection: $vm.splitStrategy) {
                                    ForEach(SplitStrategy.allCases, id: \.self) { s in
                                        Text(s.displayName).tag(s)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .tint(Color.brandPrimary)
                                .onChange(of: vm.splitStrategy) { _, _ in vm.recomputeSplits() }
                                .onChange(of: vm.amountText)    { _, _ in vm.recomputeSplits() }
                            }
                            .padding(.horizontal, XBillSpacing.base)
                        }

                        // MARK: Participants
                        VStack(alignment: .leading, spacing: XBillSpacing.sm) {
                            sectionHeader("Participants")
                            XBillCard(padding: 0) {
                                VStack(spacing: 0) {
                                    ForEach($vm.splitInputs) { $input in
                                        HStack(spacing: XBillSpacing.md) {
                                            AvatarView(name: input.displayName, url: input.avatarURL, size: XBillIcon.avatarSm)
                                            Text(input.displayName)
                                                .font(.xbillBodyMedium)
                                                .foregroundStyle(Color.textPrimary)
                                            Spacer()
                                            if vm.splitStrategy == .exact {
                                                TextField("0.00", value: $input.amount, format: .number)
                                                    .font(.xbillSmallAmount)
                                                    .keyboardType(.decimalPad)
                                                    .multilineTextAlignment(.trailing)
                                                    .frame(width: 70)
                                                    .foregroundStyle(Color.textPrimary)
                                            } else {
                                                Text(input.amount.formatted(currencyCode: vm.currency))
                                                    .font(.xbillSmallAmount)
                                                    .foregroundStyle(Color.textSecondary)
                                            }
                                            Toggle("", isOn: $input.isIncluded)
                                                .labelsHidden()
                                                .tint(Color.brandPrimary)
                                                .onChange(of: input.isIncluded) { _, _ in vm.recomputeSplits() }
                                        }
                                        .padding(.horizontal, XBillSpacing.base)
                                        .padding(.vertical, XBillSpacing.sm)

                                        if input.userID != vm.splitInputs.last?.userID {
                                            Divider().padding(.leading, XBillSpacing.base)
                                        }
                                    }

                                    if let validationError = vm.splitValidationError {
                                        Text(validationError)
                                            .font(.xbillCaption)
                                            .foregroundStyle(Color.moneyNegative)
                                            .padding(.horizontal, XBillSpacing.base)
                                            .padding(.bottom, XBillSpacing.sm)
                                    }
                                }
                            }
                            .padding(.horizontal, XBillSpacing.base)
                        }

                        // MARK: Scan receipt
                        Button {
                            receiptVM = ReceiptViewModel()
                            showReceiptScan = true
                        } label: {
                            Label("Scan Receipt", systemImage: "doc.text.viewfinder")
                                .font(.xbillButtonMedium)
                                .foregroundStyle(Color.brandPrimary)
                        }
                        .padding(.horizontal, XBillSpacing.base)

                        Spacer(minLength: XBillSpacing.xxxl)
                    }
                    .padding(.top, XBillSpacing.base)
                }
            }
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.navBarBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.brandPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .font(.xbillButtonMedium)
                        .foregroundStyle(Color.brandPrimary)
                        .disabled(!vm.canSave || vm.isLoading)
                        .overlay { if vm.isLoading { ProgressView() } }
                }
            }
            .sheet(isPresented: $showReceiptScan) {
                ReceiptScanView(
                    vm: receiptVM,
                    members: members,
                    onConfirmed: { splits in
                        applyReceiptSplits(splits: splits)
                    }
                )
            }
        }
        .errorAlert(error: $vm.error)
    }

    // MARK: - Conversion Preview

    private var conversionPreview: some View {
        Group {
            if vm.isFetchingRate {
                ProgressView()
                    .scaleEffect(0.7)
            } else if let converted = vm.convertedAmount, let rate = vm.exchangeRate {
                VStack(spacing: 2) {
                    Text("≈ \(converted.formatted(currencyCode: vm.currency))")
                        .font(.xbillBodyMedium)
                        .foregroundStyle(Color.brandPrimary)
                    Text("1 \(vm.expenseCurrency) = \(String(format: "%.4f", rate)) \(vm.currency)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, XBillSpacing.xs)
            } else {
                Text("Tap amount to fetch rate")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, XBillSpacing.xs)
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.xbillSectionTitle)
            .textCase(.uppercase)
            .foregroundStyle(Color.textTertiary)
            .padding(.horizontal, XBillSpacing.base)
    }

    private func save() async {
        await vm.save()
        if vm.isSaved {
            HapticManager.success()
            await onSaved()
            dismiss()
        }
    }

    private func applyReceiptSplits(splits: [SplitInput]) {
        vm.splitInputs   = splits
        vm.splitStrategy = .exact
        let total = receiptVM.grandTotal
        if total > .zero {
            vm.amountText = NSDecimalNumber(decimal: total).stringValue
        }
        showReceiptScan = false
    }
}

// MARK: - Category Chip

private struct CategoryChipView: View {
    let category: Expense.Category
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: XBillSpacing.xs) {
                Text(category.emoji)
                    .font(.system(size: 13))
                Text(category.displayName)
                    .font(.xbillLabel)
                    .foregroundStyle(isSelected ? Color.brandPrimary : Color.textSecondary)
            }
            .padding(.horizontal, XBillSpacing.md)
            .padding(.vertical, XBillSpacing.sm)
            .background(isSelected ? Color.brandSurface : Color.bgTertiary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.brandPrimary : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AddExpenseView(
        group: BillGroup(id: UUID(), name: "Test", emoji: "💸",
                     createdBy: UUID(), isArchived: false,
                     currency: "USD", createdAt: Date()),
        members: [],
        currentUserID: UUID(),
        onSaved: { }
    )
}
