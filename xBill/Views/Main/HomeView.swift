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
                            }
                        }
                        .padding(.horizontal, AppSpacing.lg)

                        VStack(spacing: AppSpacing.sm) {
                            ForEach(vm.groups) { group in
                                NavigationLink(value: group) {
                                    homeGroupCard(group)
                                }
                                .buttonStyle(.plain)
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
}

#Preview {
    HomeView(vm: HomeViewModel())
}
