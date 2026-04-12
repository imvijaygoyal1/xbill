import SwiftUI

struct GroupDetailView: View {
    @Bindable var vm: GroupViewModel
    let currentUserID: UUID
    @State private var showAddExpense = false
    @State private var showSettleUp = false
    @State private var showInvite = false
    @State private var showInviteLink = false
    @State private var showStats = false
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if vm.isLoading && vm.expenses.isEmpty {
                    LoadingOverlay(message: "Loading group…")
                } else {
                    content
                }
            }
            .navigationTitle(vm.group.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.navBarBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(Color.brandPrimary)
            .toolbar { toolbar }
            .task { await vm.load() }
            .refreshable { await vm.refresh() }
            .sheet(isPresented: $showAddExpense) {
                AddExpenseView(group: vm.group, members: vm.members, currentUserID: currentUserID) {
                    await vm.refresh()
                }
            }
            .sheet(isPresented: $showSettleUp) {
                SettleUpView(vm: vm)
            }
            .sheet(isPresented: $showInvite) {
                InviteMembersView(group: vm.group) {
                    await vm.load()
                }
            }
            .sheet(isPresented: $showInviteLink) {
                GroupInviteView(group: vm.group, currentUserID: currentUserID)
            }
            .navigationDestination(isPresented: $showStats) {
                GroupStatsView(
                    expenses: vm.expenses,
                    members:  vm.members,
                    currency: vm.group.currency
                )
            }
            .errorAlert(error: $vm.error)

            // FAB — only on Expenses tab
            if selectedTab == 0 {
                FABButton { showAddExpense = true }
                    .padding(.bottom, 24)
                    .padding(.trailing, 20)
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            // Segmented picker
            Picker("View", selection: $selectedTab) {
                Text("Expenses").tag(0)
                Text("Balances").tag(1)
                Text("Settle Up").tag(2)
            }
            .pickerStyle(.segmented)
            .tint(Color.brandPrimary)
            .padding(.horizontal, XBillSpacing.base)
            .padding(.vertical, XBillSpacing.sm)
            .background(Color.bgCard)

            Color.separator.frame(height: 0.5)

            // Tab content
            switch selectedTab {
            case 0: expensesTab
            case 1: balancesTab
            default: settleUpTabEmbedded
            }
        }
        .background(Color.bgSecondary)
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
                    action: { showAddExpense = true }
                )
            } else {
                List {
                    ForEach(vm.sortedExpenses) { expense in
                        NavigationLink {
                            ExpenseDetailView(
                                expense: expense,
                                members: vm.members,
                                currency: vm.group.currency,
                                currentUserID: currentUserID,
                                onUpdated: { updated in Task { await vm.updateExpense(updated) } },
                                onDeleted: { Task { await vm.deleteExpense(expense) } }
                            )
                        } label: {
                            ExpenseRowView(expense: expense, members: vm.members, showAmountBadge: true)
                        }
                        .listRowBackground(Color.bgCard)
                    }
                    .onDelete { offsets in
                        for expense in offsets.map({ vm.sortedExpenses[$0] }) {
                            Task { await vm.deleteExpense(expense) }
                        }
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
                Task {
                    await vm.recordSettlement(suggestion)
                    HapticManager.success()
                }
            }
        }
        .padding(.vertical, XBillSpacing.sm)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { showAddExpense = true } label: {
                    Label("Add Expense", systemImage: "plus")
                }
                Button { showStats = true } label: {
                    Label("Stats", systemImage: "chart.bar.fill")
                }
                Divider()
                Button { showInvite = true } label: {
                    Label("Invite via Email", systemImage: "envelope")
                }
                Button { showInviteLink = true } label: {
                    Label("Invite via Link", systemImage: "qrcode")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
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
