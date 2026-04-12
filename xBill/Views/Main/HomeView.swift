import SwiftUI

struct HomeView: View {
    @Bindable var vm: HomeViewModel
    @State private var showCreateGroup = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                scrollContent
                    .navigationTitle("xBill")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(Color.navBarBg, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .safeAreaInset(edge: .top) {
                        if !NetworkMonitor.shared.isConnected { OfflineBanner() }
                    }
                    .refreshable { await vm.refresh() }
                    .sheet(isPresented: $showCreateGroup) {
                        CreateGroupView { _ in await vm.refresh() }
                    }

                if NetworkMonitor.shared.isConnected {
                    FABButton { showCreateGroup = true }
                        .padding(.bottom, 24)
                        .padding(.trailing, 20)
                }
            }
        }
        .task { await vm.startRealtimeUpdates() }
        .errorAlert(error: $vm.error)
    }

    // MARK: - Content

    @ViewBuilder
    private var scrollContent: some View {
        if vm.isLoading && vm.groups.isEmpty {
            LoadingOverlay(message: "Loading groups…")
        } else if vm.groups.isEmpty {
            EmptyStateView(
                icon: "person.3.fill",
                title: "No Groups Yet",
                message: "Create a group to start splitting expenses with friends.",
                actionLabel: "Create Group",
                action: { showCreateGroup = true }
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: XBillSpacing.xl) {
                    // Balance hero card
                    BalanceHeroCard(
                        label: vm.netBalance >= .zero ? "You are owed" : "You owe",
                        amount: abs(vm.netBalance),
                        subtitle: "\(vm.groups.count) group\(vm.groups.count == 1 ? "" : "s")",
                        isPositive: vm.netBalance >= .zero
                    )
                    .padding(.horizontal, XBillSpacing.base)

                    // Quick stats
                    HStack(spacing: XBillSpacing.sm) {
                        quickStatCard(label: "Owed to you", amount: vm.totalOwed, direction: .positive)
                        quickStatCard(label: "You owe",     amount: vm.totalOwing, direction: .negative)
                    }
                    .padding(.horizontal, XBillSpacing.base)

                    // My Groups — horizontal chips
                    VStack(alignment: .leading, spacing: XBillSpacing.sm) {
                        Text("MY GROUPS")
                            .font(.xbillSectionTitle)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.textTertiary)
                            .padding(.horizontal, XBillSpacing.base)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: XBillSpacing.sm) {
                                ForEach(vm.groups) { group in
                                    NavigationLink(value: group) {
                                        GroupChipView(group: group)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, XBillSpacing.base)
                        }
                    }

                    // Recent Expenses
                    if !vm.recentExpenses.isEmpty {
                        VStack(alignment: .leading, spacing: XBillSpacing.sm) {
                            Text("RECENT EXPENSES")
                                .font(.xbillSectionTitle)
                                .textCase(.uppercase)
                                .foregroundStyle(Color.textTertiary)
                                .padding(.horizontal, XBillSpacing.base)

                            LazyVStack(spacing: 0) {
                                ForEach(vm.recentExpenses) { entry in
                                    ExpenseRowView(expense: entry.expense, members: entry.members)
                                        .padding(.horizontal, XBillSpacing.base)
                                        .padding(.vertical, XBillSpacing.xs)
                                        .background(Color.bgCard)

                                    if entry.id != vm.recentExpenses.last?.id {
                                        Divider()
                                            .padding(.leading, XBillSpacing.base + XBillIcon.categorySize + XBillSpacing.md)
                                    }
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: XBillRadius.lg))
                            .overlay(
                                RoundedRectangle(cornerRadius: XBillRadius.lg)
                                    .stroke(Color.separator, lineWidth: 0.5)
                            )
                            .padding(.horizontal, XBillSpacing.base)
                        }
                    }
                }
                .padding(.top, XBillSpacing.base)
                .padding(.bottom, 100)
            }
            .background(Color.bgSecondary)
            .navigationDestination(for: BillGroup.self) { group in
                GroupDetailView(
                    vm: GroupViewModel(group: group),
                    currentUserID: vm.currentUser?.id ?? UUID()
                )
            }
        }
    }

    // MARK: - Quick Stat Card

    private func quickStatCard(label: String, amount: Decimal, direction: AmountDirection) -> some View {
        VStack(alignment: .leading, spacing: XBillSpacing.xs) {
            Text(label)
                .font(.xbillCaption)
                .foregroundStyle(Color.textTertiary)
            Text(amount.formatted(currencyCode: "USD"))
                .font(.xbillMediumAmount)
                .foregroundStyle(direction == .positive ? Color.moneyPositive : Color.moneyNegative)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(XBillSpacing.md)
        .background(direction == .positive ? Color.moneyPositiveBg : Color.moneyNegativeBg)
        .clipShape(RoundedRectangle(cornerRadius: XBillRadius.md))
    }
}

#Preview {
    HomeView(vm: HomeViewModel())
}
