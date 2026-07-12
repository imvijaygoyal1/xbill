//
//  GroupDetailView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct GroupDetailView: View {
    @Bindable var vm: GroupViewModel
    let currentUserID: UUID
    var onGroupStatusChanged: (() async -> Void)?
    @State private var showAddExpense = false
    @State private var showInvite = false
    @State private var showInviteLink = false
    @State private var showGroupSettings = false
    @State private var showStats = false
    @State private var showArchiveConfirm = false
    @State private var showUnarchiveConfirm = false
    @State private var expenseToDelete: Expense?
    @State private var settlementToConfirm: SettlementSuggestion?
    @State private var shareItem: ExportShareItem?
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var filterCategory: Expense.Category? = nil
    @Environment(\.dismiss) private var dismiss

    private var filteredExpenses: [Expense] {
        var result = vm.sortedExpenses
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter { exp in
                exp.title.lowercased().contains(q) ||
                exp.category.displayName.lowercased().contains(q) ||
                (exp.notes?.lowercased().contains(q) == true)
            }
        }
        if let cat = filterCategory {
            result = result.filter { $0.category == cat }
        }
        return result
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if vm.isLoading && vm.expenses.isEmpty {
                    LoadingOverlay(message: "Loading group…")
                } else {
                    content
                }
            }
            .navigationBarBackButtonHidden()
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(AppColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(Color.brandPrimary)
            .safeAreaInset(edge: .top) {
                if !NetworkMonitor.shared.isConnected { OfflineBanner() }
            }
            .task {
                await vm.load()
                // createDueRecurringInstances is idempotent per cycle (advances the template
                // date after creating the instance). Run only on first appear; navigation-away
                // cancellation leaves already-created instances in place (correct state).
                await vm.createDueRecurringInstances(currentUserID: currentUserID)
            }
            .refreshable { await vm.refresh() }
            .onChange(of: selectedTab) { _, _ in
                searchText = ""
                filterCategory = nil
            }
            .sheet(isPresented: $showAddExpense) {
                AddExpenseView(group: vm.group, members: vm.activeMembers, currentUserID: currentUserID) { savedExpense in
                    vm.recordCreatedExpense(savedExpense)
                }
            }
            .sheet(isPresented: $showGroupSettings) {
                GroupSettingsView(vm: vm, currentUserID: currentUserID) {
                    await onGroupStatusChanged?()
                }
            }
            .sheet(isPresented: $showInvite) {
                InviteMembersView(group: vm.group) {
                    await vm.load()
                    await onGroupStatusChanged?()
                }
            }
            .sheet(isPresented: $showInviteLink) {
                GroupInviteView(group: vm.group, currentUserID: currentUserID)
            }
            .sheet(item: $shareItem) { item in
                ShareSheetView(url: item.url)
                    .ignoresSafeArea()
            }
            .confirmationDialog(
                "Archive \"\(vm.group.name)\"?",
                isPresented: $showArchiveConfirm,
                titleVisibility: .visible
            ) {
                Button("Archive Group", role: .destructive) {
                    Task {
                        await vm.archiveGroup()
                        await onGroupStatusChanged?()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if vm.settlementSuggestions.isEmpty {
                    Text("The group will be hidden from your active list. You can unarchive it later from the Groups tab.")
                } else {
                    Text("This group has \(vm.settlementSuggestions.count) unsettled balance\(vm.settlementSuggestions.count == 1 ? "" : "s"). It will be hidden from your active list — you can unarchive it later from the Groups tab.")
                }
            }
            .confirmationDialog(
                "Unarchive \"\(vm.group.name)\"?",
                isPresented: $showUnarchiveConfirm,
                titleVisibility: .visible
            ) {
                Button("Unarchive Group") {
                    Task {
                        await vm.unarchiveGroup()
                        await onGroupStatusChanged?()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The group will be moved back to your active list.")
            }
            .confirmationDialog(
                "Delete Expense?",
                isPresented: Binding(
                    get: { expenseToDelete != nil },
                    set: { if !$0 { expenseToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    guard let expense = expenseToDelete else { return }
                    Task { await vm.deleteExpense(expense) }
                    expenseToDelete = nil
                }
                Button("Cancel", role: .cancel) { expenseToDelete = nil }
            } message: {
                Text("This will remove the expense and all its splits. This cannot be undone.")
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
                    guard let suggestion = settlementToConfirm else { return }
                    Task {
                        await vm.recordSettlement(suggestion)
                        HapticManager.success()
                    }
                    settlementToConfirm = nil
                }
                Button("Cancel", role: .cancel) { settlementToConfirm = nil }
            } message: {
                if let s = settlementToConfirm {
                    Text("\(s.fromName) → \(s.toName): \(s.amount.formatted(currencyCode: s.currency)). This cannot be undone.")
                }
            }
            .navigationDestination(isPresented: $showStats) {
                GroupStatsView(
                    expenses: vm.expenses,
                    members:  vm.members,
                    currency: vm.group.currency
                )
            }
            .errorAlert(item: $vm.errorAlert)

            // Keep the primary action visible offline, then explain why it cannot continue.
            if selectedTab == 0 {
                FABButton { openAddExpense() }
                    .accessibilityLabel(NetworkMonitor.shared.isConnected ? "Add Expense" : "Add Expense unavailable offline")
                    .padding(.bottom, AppSpacing.floatingActionBottomPadding)
                    .padding(.trailing, AppSpacing.md)
            }
        }
        .searchable(text: $searchText, prompt: "Search expenses")
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            XBillPageHeader(
                title: vm.group.name,
                subtitle: "\(vm.group.currency) group",
                showsBackButton: true,
                backAction: { dismiss() },
                trailing: { groupMenu }
            )

            groupSummaryHeader

            // Segmented picker
            XBillSegmentedControl(
                options: [(0, "Expenses"), (1, "Balances"), (2, "Settle Up")],
                selection: $selectedTab
            )
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(AppColors.surface)

            AppColors.border.frame(height: 0.5)

            // Category filter strip (expenses tab only)
            if selectedTab == 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: XBillSpacing.xs) {
                        ExpenseFilterChip(label: "All", isSelected: filterCategory == nil) {
                            filterCategory = nil
                        }
                        ForEach(Expense.Category.allCases, id: \.self) { cat in
                            ExpenseFilterChip(
                                label: cat.displayName,
                                category: cat,
                                isSelected: filterCategory == cat
                            ) {
                                filterCategory = filterCategory == cat ? nil : cat
                            }
                        }
                    }
                    .padding(.horizontal, XBillSpacing.base)
                    .padding(.vertical, XBillSpacing.xs)
                }
                .background(AppColors.surface)

                AppColors.border.frame(height: 0.5)
            }

            // Tab content
            switch selectedTab {
            case 0: expensesTab
            case 1:
                if vm.isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    balancesTab
                }
            default:
                if vm.isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    settleUpTabEmbedded
                }
            }
        }
        .background(AppColors.background)
    }

    private var groupSummaryHeader: some View {
        HStack(spacing: AppSpacing.md) {
            XBillAvatarPlaceholder(name: vm.group.emoji, size: 56)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.sm) {
                    XBillAvatarStack(users: vm.activeMembers, maxVisible: 4, size: 28)
                    Text("\(vm.activeMembers.count) active member\(vm.activeMembers.count == 1 ? "" : "s")")
                        .font(.appCaption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            Spacer()
            XBillPillButton(title: "Manage", icon: "slider.horizontal.3", style: .secondary) {
                showGroupSettings = true
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.background)
    }

    // MARK: - Expenses Tab

    private var expensesTab: some View {
        Group {
            if vm.sortedExpenses.isEmpty {
                EmptyStateView(
                    icon: "receipt.fill",
                    title: "No Expenses",
                    message: "Add the first expense to this group.",
                    actionLabel: "Add Expense",
                    action: { openAddExpense() }
                )
            } else if filteredExpenses.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No Results",
                    message: !searchText.isEmpty
                        ? "No expenses match your search."
                        : filterCategory != nil
                            ? "No expenses in this category."
                            : "No expenses found."
                )
            } else {
                List {
                    ForEach(filteredExpenses) { expense in
                        NavigationLink {
                            ExpenseDetailView(
                                expense: expense,
                                members: vm.members,
                                currency: vm.group.currency,
                                groupName: vm.group.name,
                                currentUserID: currentUserID,
                                onUpdated: { updated in Task { await vm.updateExpense(updated) } },
                                onDeleted: { Task { await vm.deleteExpense(expense) } }
                            )
                        } label: {
                            ExpenseRowView(expense: expense, members: vm.members, showAmountBadge: true)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(expense.title) expense, \(expense.amount.formatted(currencyCode: expense.currency))")
                        .accessibilityIdentifier("xBill.expenseRow.\(expense.title)")
                        .listRowBackground(Color.bgCard)
                    }
                    .onDelete { offsets in
                        // Show confirmation before deleting; actual delete fires from the dialog.
                        expenseToDelete = offsets.map({ filteredExpenses[$0] }).first
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .listRowSeparatorTint(Color.separator)
            }
        }
    }

    // MARK: - Balances Tab

    private var balancesTab: some View {
        List {
            ForEach(vm.members) { member in
                let balance = vm.balance(for: member.id)
                HStack(spacing: XBillSpacing.md) {
                    AvatarView(name: member.displayName, url: member.avatarURL, size: XBillIcon.avatarSm)
                    Text(member.displayName)
                        .font(.xbillBodyMedium)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    AmountBadge(
                        amount: abs(balance),
                        direction: balance > .zero ? .positive : balance < .zero ? .negative : .settled,
                        currency: vm.group.currency
                    )
                }
                .listRowBackground(Color.bgCard)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listRowSeparatorTint(Color.separator)
    }

    // MARK: - Settle Up Tab (embedded)

    private var settleUpTabEmbedded: some View {
        List {
            if vm.settlementSuggestions.isEmpty {
                EmptyStateView(
                    icon: "checkmark.circle.fill",
                    title: "All Settled Up!",
                    message: "No outstanding balances in this group."
                )
                .listRowBackground(Color.bgCard)
                .listRowSeparator(.hidden)
            } else {
                ForEach(vm.settlementSuggestions) { suggestion in
                    settlementRow(suggestion)
                        .listRowBackground(Color.bgCard)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listRowSeparatorTint(Color.separator)
    }

    private func settlementRow(_ suggestion: SettlementSuggestion) -> some View {
        VStack(spacing: XBillSpacing.md) {
            HStack(spacing: XBillSpacing.md) {
                AvatarView(name: suggestion.fromName, size: XBillIcon.avatarSm)
                Image(systemName: "arrow.right")
                    .foregroundStyle(Color.brandAccent)
                AvatarView(name: suggestion.toName, size: XBillIcon.avatarSm)
                Spacer()
                Text(suggestion.amount.formatted(currencyCode: suggestion.currency))
                    .font(.xbillLargeAmount)
                    .foregroundStyle(Color.textPrimary)
            }
            XBillButton(title: "Mark as Settled", style: .primary) {
                settlementToConfirm = suggestion
            }
            if let recipient = vm.members.first(where: { $0.id == suggestion.toUserID }) {
                HStack(spacing: AppSpacing.sm) {
                    if let venmoURL = PaymentLinkService.shared.paymentLink(for: suggestion, recipient: recipient, method: .venmo) {
                        Link(destination: venmoURL) {
                            Label("Venmo", systemImage: "link")
                                .font(.appCaptionMedium)
                        }
                    }
                    if let paypalURL = PaymentLinkService.shared.paymentLink(for: suggestion, recipient: recipient, method: .paypal) {
                        Link(destination: paypalURL) {
                            Label("PayPal", systemImage: "link")
                                .font(.appCaptionMedium)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, XBillSpacing.sm)
    }

    // MARK: - Toolbar

    private var groupMenu: some View {
        Menu {
            Button { openAddExpense() } label: {
                Label("Add Expense", systemImage: "plus")
            }
            Button { showStats = true } label: {
                Label("Stats", systemImage: "chart.bar.fill")
            }
            Button { showGroupSettings = true } label: {
                Label("Manage Group", systemImage: "slider.horizontal.3")
            }

            Divider()

            Menu {
                Button { exportCSV() } label: {
                    Label("Export CSV", systemImage: "tablecells")
                }
                Button { exportPDF() } label: {
                    Label("Export PDF", systemImage: "doc.richtext")
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button { showInvite = true } label: {
                Label("Invite via Email", systemImage: "envelope")
            }
            Button { showInviteLink = true } label: {
                Label("Invite via Link", systemImage: "qrcode")
            }

            Divider()

            if vm.group.isArchived {
                Button {
                    showUnarchiveConfirm = true
                } label: {
                    Label("Unarchive Group", systemImage: "tray.and.arrow.up")
                }
            } else {
                Button(role: .destructive) {
                    showArchiveConfirm = true
                } label: {
                    Label("Archive Group", systemImage: "archivebox")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(AppColors.primary)
                .frame(width: AppSpacing.tapTarget, height: AppSpacing.tapTarget)
        }
        .accessibilityLabel("Group actions")
    }

    // MARK: - Export

    private func openAddExpense() {
        guard NetworkMonitor.shared.isConnected else {
            vm.errorAlert = ErrorAlert(
                title: "You're Offline",
                message: "Connect to the internet before adding an expense."
            )
            return
        }
        showAddExpense = true
    }

    private func exportCSV() {
        let names = vm.memberNames
        let data = ExportService.shared.generateCSV(
            group: vm.group,
            expenses: vm.expenses,
            memberNames: names
        )
        let filename = "\(vm.group.name.sanitizedForFilename)_expenses.csv"
        do {
            let url = try ExportService.shared.writeTemp(data: data, filename: filename)
            shareItem = ExportShareItem(url: url)
        } catch {
            vm.errorAlert = ErrorAlert(title: "Export Failed", message: error.localizedDescription)
        }
    }

    private func exportPDF() {
        let names = vm.memberNames
        let data = ExportService.shared.generatePDF(
            group: vm.group,
            expenses: vm.expenses,
            memberNames: names,
            balances: vm.balances
        )
        let filename = "\(vm.group.name.sanitizedForFilename)_expenses.pdf"
        do {
            let url = try ExportService.shared.writeTemp(data: data, filename: filename)
            shareItem = ExportShareItem(url: url)
        } catch {
            vm.errorAlert = ErrorAlert(title: "Export Failed", message: error.localizedDescription)
        }
    }
}

// MARK: - Group Settings

private struct GroupSettingsView: View {
    @Bindable var vm: GroupViewModel
    let currentUserID: UUID
    let onChanged: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var emoji: String
    @State private var currency: String
    @State private var showInvite = false
    @State private var showInviteLink = false
    @State private var memberToRemove: User?

    private let icons = ["🏠", "✈️", "🍽️", "🎉", "🏖️", "🏢", "🎮", "🚗", "🎵", "💼"]

    init(vm: GroupViewModel, currentUserID: UUID, onChanged: @escaping () async -> Void) {
        self.vm = vm
        self.currentUserID = currentUserID
        self.onChanged = onChanged
        _name = State(initialValue: vm.group.name)
        _emoji = State(initialValue: vm.group.emoji)
        _currency = State(initialValue: vm.group.currency)
    }

    private var isOwner: Bool {
        vm.group.createdBy == currentUserID
    }

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !vm.isLoading else { return false }
        let currencyChanged = vm.canChangeCurrency && currency != vm.group.currency
        return trimmed != vm.group.name || emoji != vm.group.emoji || currencyChanged
    }

    var body: some View {
        NavigationStack {
            XBillScreenContainer(
                horizontalPadding: AppSpacing.lg,
                contentSpacing: AppSpacing.xl,
                bottomPadding: AppSpacing.xl
            ) {
                XBillPageHeader(
                    title: "Manage Group",
                    subtitle: "Edit details, invites, and members.",
                    showsBackButton: true,
                    backAction: { dismiss() }
                )
                .padding(.horizontal, -AppSpacing.lg)

                detailsSection
                inviteSection
                membersSection
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showInvite) {
                InviteMembersView(group: vm.group) {
                    await vm.load()
                    await onChanged()
                }
            }
            .sheet(isPresented: $showInviteLink) {
                GroupInviteView(group: vm.group, currentUserID: currentUserID)
            }
            .confirmationDialog(
                "Remove Member?",
                isPresented: Binding(
                    get: { memberToRemove != nil },
                    set: { if !$0 { memberToRemove = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    guard let member = memberToRemove else { return }
                    Task {
                        await vm.removeMember(userID: member.id)
                        if vm.errorAlert == nil {
                            await onChanged()
                            memberToRemove = nil
                        }
                    }
                }
                Button("Cancel", role: .cancel) { memberToRemove = nil }
            } message: {
                if let memberToRemove {
                    Text("\(memberToRemove.displayName) will lose access to this group. Their historical expenses and splits stay visible.")
                }
            }
        }
        .errorAlert(item: $vm.errorAlert)
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            XBillSectionHeader("Details")
            XBillFormSection {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    XBillTextField(placeholder: "Group name", text: $name)
                        .accessibilityLabel("Group name")

                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Icon")
                            .font(.appCaptionMedium)
                            .foregroundStyle(AppColors.textSecondary)
                        XBillIconPickerGrid(icons: icons, selectedIcon: $emoji)
                    }

                    HStack(spacing: AppSpacing.md) {
                        Text("Currency")
                            .font(.appBody)
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Picker("Currency", selection: $currency) {
                            ForEach(ExchangeRateService.commonCurrencies, id: \.self) { code in
                                Text(code).tag(code)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(AppColors.primary)
                        .disabled(!vm.canChangeCurrency)
                    }
                    if !vm.canChangeCurrency {
                        Text("Currency is locked after the first expense to keep historical amounts accurate.")
                            .font(.appCaption)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    XBillPrimaryButton(
                        title: "Save Changes",
                        icon: "checkmark",
                        isLoading: vm.isLoading,
                        isDisabled: !canSave
                    ) {
                        Task {
                            await vm.updateGroupDetails(name: name, emoji: emoji, currency: currency)
                            name = vm.group.name
                            emoji = vm.group.emoji
                            currency = vm.group.currency
                            await onChanged()
                        }
                    }
                }
            }
        }
    }

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            XBillSectionHeader("Invites")
            XBillActionCard(
                icon: "envelope.fill",
                title: "Invite by Email",
                subtitle: "Send a group invite to a member."
            ) {
                showInvite = true
            }
            XBillActionCard(
                icon: "qrcode",
                title: "Invite Link",
                subtitle: "Share a reusable link or QR code."
            ) {
                showInviteLink = true
            }
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            XBillSectionHeader("Members", subtitle: "\(vm.activeMembers.count) active · \(vm.members.count) historical")
            XBillFormSection {
                VStack(spacing: 0) {
                    ForEach(Array(vm.members.enumerated()), id: \.element.id) { index, member in
                        memberRow(member)
                        if index < vm.members.count - 1 {
                            Divider()
                                .overlay(AppColors.border)
                        }
                    }

                    if vm.members.isEmpty {
                        Text("Members will appear after the group finishes loading.")
                            .font(.appCaption)
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if !isOwner {
                Text("Only the group owner can remove members.")
                    .font(.appCaption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private func memberRow(_ member: User) -> some View {
        HStack(spacing: AppSpacing.md) {
            AvatarView(name: member.displayName, url: member.avatarURL, size: XBillIcon.avatarSm)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(member.displayName)
                    .font(.appBody)
                    .foregroundStyle(AppColors.textPrimary)
                if !member.email.isEmpty {
                    Text(member.email)
                        .font(.appCaption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()

            if vm.group.createdBy == member.id {
                Text("Owner")
                    .font(.appCaptionMedium)
                    .foregroundStyle(AppColors.primary)
                    .padding(.horizontal, AppSpacing.sm)
                    .frame(minHeight: 28)
                    .background(AppColors.surfaceSoft)
                    .clipShape(Capsule())
            } else if isOwner {
                Button(role: .destructive) {
                    memberToRemove = member
                } label: {
                    Image(systemName: member.isActive ? "person.crop.circle.badge.minus" : "clock.badge")
                        .font(.appTitle)
                        .foregroundStyle(member.isActive ? AppColors.error : AppColors.textTertiary)
                        .frame(width: AppSpacing.tapTarget, height: AppSpacing.tapTarget)
                }
                .buttonStyle(.plain)
                .disabled(!member.isActive)
                .accessibilityLabel("Remove \(member.displayName)")
            }
            if !member.isActive {
                Text("Inactive")
                    .font(.appCaptionMedium)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, AppSpacing.sm)
                    .frame(minHeight: 28)
                    .background(AppColors.surfaceSoft)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, AppSpacing.sm)
    }
}

// MARK: - Filter Chip

private struct ExpenseFilterChip: View {
    let label: String
    var category: Expense.Category? = nil
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: XBillSpacing.xs) {
                if let category {
                    XBillCategoryIcon(category: category, size: 22)
                }
                Text(label)
                    .font(.xbillLabel)
                    .foregroundStyle(isSelected ? Color.brandPrimary : Color.textSecondary)
            }
            .padding(.horizontal, XBillSpacing.md)
            .padding(.vertical, XBillSpacing.xs)
            .background(isSelected ? Color.brandSurface : Color.bgTertiary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.brandPrimary : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .frame(minHeight: AppSpacing.tapTarget)
    }
}

// MARK: - Export helpers

struct ExportShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private extension String {
    var sanitizedForFilename: String {
        self.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "_")
            .lowercased()
    }
}

#Preview {
    NavigationStack {
        GroupDetailView(
            vm: GroupViewModel(group: BillGroup(
                id: UUID(), name: "Weekend Trip", emoji: "✈️",
                createdBy: UUID(), isArchived: false,
                currency: "USD", createdAt: Date()
            )),
            currentUserID: UUID()
        )
    }
}
