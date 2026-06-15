//
//  HomeView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct HomeView: View {
    @Bindable var vm: HomeViewModel
    @State private var showCreateGroup = false
    @State private var showQuickAddExpense = false
    @State private var quickActionScan = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                AppColors.background.ignoresSafeArea()
                scrollContent
                    .toolbar(.hidden, for: .navigationBar)
                    .toolbarBackground(AppColors.background, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .safeAreaInset(edge: .top) {
                        if !NetworkMonitor.shared.isConnected { OfflineBanner() }
                    }
                    .refreshable { await vm.refresh() }
                    .sheet(isPresented: $showCreateGroup) {
                        CreateGroupView(
                            onCreated: { _ in await vm.refresh() },
                            inviterName: vm.currentUser?.displayName ?? "Someone"
                        )
                    }
                    .sheet(isPresented: $showQuickAddExpense) {
                        if let userID = vm.currentUser?.id {
                            QuickAddExpenseSheet(
                                groups: vm.groups,
                                currentUserID: userID,
                                startWithScan: quickActionScan,
                                onSaved: { await vm.loadAll() }
                            )
                        }
                    }
            }
        }
        .task { vm.startRealtimeUpdates() }
        .errorAlert(item: $vm.errorAlert)
    }

    // MARK: - Helpers

    private func homeGroupCard(_ group: BillGroup) -> some View {
        let net = vm.groupNetBalances[group.id] ?? .zero
        let memberCount = vm.groupMemberCounts[group.id] ?? 0
        let subtitle = memberCount > 0
            ? "\(memberCount) member\(memberCount == 1 ? "" : "s") · \(group.currency)"
            : group.currency
        return XBillGroupCard(
            group: group,
            subtitle: subtitle,
            balanceLabel: net != .zero ? (net > 0 ? "Owed to you" : "You owe") : nil,
            balanceAmount: net != .zero ? abs(net) : nil,
            balanceDirection: net > 0 ? .positive : .negative,
            showsStatusChip: false,
            showsChevron: true
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var scrollContent: some View {
        if vm.isLoading && vm.groups.isEmpty {
            LoadingOverlay(message: "Loading groups…")
        } else if vm.groups.isEmpty {
            XBillScreenContainer(bottomPadding: AppSpacing.floatingActionBottomPadding) {
                EmptyStateView(
                    icon: "person.3.fill",
                    title: "No Groups Yet",
                    message: "Create a group to start splitting expenses with friends.",
                    actionLabel: "Create Group",
                    action: { showCreateGroup = true },
                    illustration: .groups
                )
            }
        } else {
            XBillScrollView(
                horizontalPadding: 0,
                bottomPadding: AppSpacing.floatingActionBottomPadding + AppSpacing.lg,
                spacing: AppSpacing.lg
            ) {
                    dashboardHeader

                    BalanceHeroCard(
                        label: vm.netBalance == .zero ? "All settled" : vm.netBalance > .zero ? "Net balance owed to you" : "Net balance you owe",
                        amount: abs(vm.netBalance),
                        subtitle: "\(vm.groups.count) group\(vm.groups.count == 1 ? "" : "s")",
                        isPositive: vm.netBalance >= .zero
                    )
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.sm)

                    HStack(spacing: AppSpacing.sm) {
                        XBillMetricCard(
                            title: "Owed to you",
                            amount: vm.totalOwed,
                            direction: .positive
                        )
                        XBillMetricCard(
                            title: "You owe",
                            amount: vm.totalOwing,
                            direction: .negative
                        )
                    }
                    .padding(.horizontal, AppSpacing.lg)

                    quickActions

                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        XBillSectionHeader("My Groups", subtitle: "\(vm.groups.count) active") {
                            if NetworkMonitor.shared.isConnected {
                                Button {
                                    showCreateGroup = true
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.appIcon)
                                        .foregroundStyle(AppColors.textInverse)
                                        .frame(width: AppSpacing.tapTarget, height: AppSpacing.tapTarget)
                                        .background(AppColors.primary)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Create group")
                                .accessibilityIdentifier("xBill.groups.createButton")
                            }
                        }
                        .accessibilityIdentifier("xBill.home.groupsHeader")
                        .padding(.horizontal, AppSpacing.lg)

                        VStack(spacing: AppSpacing.sm) {
                            ForEach(vm.groups) { group in
                                NavigationLink(value: group) {
                                    homeGroupCard(group)
                                }
                                .buttonStyle(.plain)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(group.name) group, active, \(group.currency)")
                                .accessibilityIdentifier("xBill.group.active.\(group.id.uuidString)")
                            }
                        }
                        .padding(.horizontal, AppSpacing.lg)
                    }

                    if !vm.crossGroupSuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            XBillSectionHeader("Simplify Debts")
                                .padding(.horizontal, AppSpacing.lg)

                            LazyVStack(spacing: 0) {
                                ForEach(vm.crossGroupSuggestions) { suggestion in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(suggestion.fromName)
                                            .font(.appBody)
                                            .foregroundStyle(AppColors.textPrimary)
                                            Text("→ \(suggestion.toName)")
                                                .font(.appCaption)
                                                .foregroundStyle(AppColors.textSecondary)
                                        }
                                        Spacer()
                                        AmountBadge(amount: suggestion.amount,
                                                    direction: .negative,
                                                    currency: suggestion.currency)
                                    }
                                    .padding(.horizontal, AppSpacing.md)
                                    .padding(.vertical, AppSpacing.sm)

                                    if suggestion.id != vm.crossGroupSuggestions.last?.id {
                                        Divider().padding(.leading, XBillSpacing.base)
                                    }
                                }
                            }
                            .asSharpCard()
                            .padding(.horizontal, AppSpacing.lg)
                        }
                    }

                    if !vm.recentExpenses.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            XBillSectionHeader("Recent Expenses")
                                .padding(.horizontal, AppSpacing.lg)

                            LazyVStack(spacing: 0) {
                                ForEach(vm.recentExpenses) { entry in
                                    let group = vm.groups.first(where: { $0.id == entry.expense.groupID })
                                    NavigationLink {
                                        if let userID = vm.currentUser?.id {
                                            ExpenseDetailView(
                                                expense: entry.expense,
                                                members: entry.members,
                                                currency: group?.currency ?? entry.expense.currency,
                                                groupName: group?.name ?? "",
                                                currentUserID: userID
                                            )
                                        }
                                    } label: {
                                        ExpenseRowView(expense: entry.expense, members: entry.members)
                                            .padding(.horizontal, AppSpacing.md)
                                            .padding(.vertical, AppSpacing.xs)
                                    }
                                    .buttonStyle(.plain)

                                    if entry.id != vm.recentExpenses.last?.id {
                                        Divider()
                                            .padding(.leading, XBillSpacing.base + XBillIcon.categorySize + XBillSpacing.md)
                                    }
                                }
                            }
                            .asSharpCard()
                            .padding(.horizontal, AppSpacing.lg)
                        }
                    }
            }
            .background(AppColors.background)
            .navigationDestination(for: BillGroup.self) { group in
                if let userID = vm.currentUser?.id {
                    GroupDetailView(
                        vm: GroupViewModel(group: group),
                        currentUserID: userID
                    )
                } else {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var dashboardHeader: some View {
        XBillScreenHeader(
            title: "Home",
            subtitle: NetworkMonitor.shared.isConnected
                ? "Track balances and add expenses across your groups."
                : "Offline mode. You can review cached groups, but changes need a connection."
        )
        .padding(.horizontal, AppSpacing.lg)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            XBillSectionHeader("Quick Actions")
                .padding(.horizontal, AppSpacing.lg)

            HStack(spacing: AppSpacing.sm) {
                quickActionCard(
                    icon: "plus.circle.fill",
                    title: "Add Expense",
                    subtitle: actionSubtitle,
                    isEnabled: canAddExpense
                ) {
                    quickActionScan = false
                    showQuickAddExpense = true
                }

                quickActionCard(
                    icon: "doc.text.viewfinder",
                    title: "Scan Receipt",
                    subtitle: actionSubtitle,
                    isEnabled: canAddExpense
                ) {
                    quickActionScan = true
                    showQuickAddExpense = true
                }
            }
            .padding(.horizontal, AppSpacing.lg)
        }
    }

    private var canAddExpense: Bool {
        NetworkMonitor.shared.isConnected && !vm.groups.isEmpty && vm.currentUser != nil
    }

    private var actionSubtitle: String {
        if !NetworkMonitor.shared.isConnected { return "Unavailable offline" }
        if vm.groups.isEmpty { return "Create a group first" }
        return "Choose a group"
    }

    private func quickActionCard(
        icon: String,
        title: String,
        subtitle: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Image(systemName: icon)
                    .font(.appH2)
                    .foregroundStyle(isEnabled ? AppColors.primary : AppColors.textTertiary)
                    .frame(width: AppSpacing.tapTarget, height: AppSpacing.tapTarget)
                    .background(AppColors.surfaceSoft)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(title)
                        .font(.appTitle)
                        .foregroundStyle(isEnabled ? AppColors.textPrimary : AppColors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(subtitle)
                        .font(.appCaption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 118)
            .padding(AppSpacing.md)
            .background(isEnabled ? AppColors.surface : AppColors.surfaceSoft)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .stroke(AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

#Preview {
    HomeView(vm: HomeViewModel())
}
