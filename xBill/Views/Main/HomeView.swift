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
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            XBillWordmark()
                        }
                    }
                    .toolbarBackground(AppColors.background, for: .navigationBar)
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
                        .padding(.bottom, AppSpacing.floatingActionBottomPadding)
                        .padding(.trailing, AppSpacing.md)
                }
            }
        }
        .task { await vm.startRealtimeUpdates() }
        .errorAlert(item: $vm.errorAlert)
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
                LazyVStack(alignment: .leading, spacing: AppSpacing.md) {
                    HomeHeader(user: vm.currentUser, balance: vm.netBalance)
                        .padding(.horizontal, AppSpacing.md)

                    // Balance hero card
                    BalanceHeroCard(
                        label: vm.netBalance >= .zero ? "You are owed" : "You owe",
                        amount: abs(vm.netBalance),
                        subtitle: "\(vm.groups.count) group\(vm.groups.count == 1 ? "" : "s")",
                        isPositive: vm.netBalance >= .zero
                    )
                    .padding(.horizontal, AppSpacing.md)

                    // Quick stats
                    HStack(spacing: AppSpacing.sm) {
                        quickStatCard(label: "Owed to you", amount: vm.totalOwed, direction: .positive)
                        quickStatCard(label: "You owe",     amount: vm.totalOwing, direction: .negative)
                    }
                    .padding(.horizontal, AppSpacing.md)

                    XBillActionCard(
                        icon: "person.badge.plus",
                        title: "Invite friends",
                        subtitle: "Start splitting with your people"
                    ) {
                        showCreateGroup = true
                    }
                    .padding(.horizontal, AppSpacing.md)

                    // My Groups — horizontal chips
                    VStack(alignment: .leading, spacing: XBillSpacing.sm) {
                        Text("MY GROUPS")
                            .font(.appCaptionMedium)
                            .tracking(1.08)
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.horizontal, AppSpacing.md)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppSpacing.sm) {
                                ForEach(vm.groups) { group in
                                    NavigationLink(value: group) {
                                        GroupChipView(group: group)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, AppSpacing.md)
                        }
                    }

                    // Cross-Group Settlements
                    if !vm.crossGroupSuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: XBillSpacing.sm) {
                            Text("SIMPLIFY DEBTS")
                                .font(.appCaptionMedium)
                                .tracking(1.08)
                                .foregroundStyle(AppColors.textSecondary)
                                .padding(.horizontal, AppSpacing.md)

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
                            .padding(.horizontal, XBillSpacing.base)
                        }
                    }

                    // Recent Expenses
                    if !vm.recentExpenses.isEmpty {
                        VStack(alignment: .leading, spacing: XBillSpacing.sm) {
                            Text("RECENT EXPENSES")
                                .font(.appCaptionMedium)
                                .tracking(1.08)
                                .foregroundStyle(AppColors.textSecondary)
                                .padding(.horizontal, AppSpacing.md)

                            LazyVStack(spacing: 0) {
                                ForEach(vm.recentExpenses) { entry in
                                    ExpenseRowView(expense: entry.expense, members: entry.members)
                                        .padding(.horizontal, AppSpacing.md)
                                        .padding(.vertical, AppSpacing.xs)

                                    if entry.id != vm.recentExpenses.last?.id {
                                        Divider()
                                            .padding(.leading, XBillSpacing.base + XBillIcon.categorySize + XBillSpacing.md)
                                    }
                                }
                            }
                            .asSharpCard()
                            .padding(.horizontal, XBillSpacing.base)
                        }
                    }
                }
                .padding(.top, AppSpacing.md)
                .padding(.bottom, AppSpacing.floatingActionBottomPadding + AppSpacing.lg)
            }
            .background(AppColors.background)
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
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(label)
                .font(.appCaptionMedium)
                .tracking(1.08)
                .foregroundStyle(AppColors.textSecondary)
            Text(amount.formatted(currencyCode: "USD"))
                .font(.appAmountSm)
                .foregroundStyle(direction == .positive ? AppColors.success : AppColors.error)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .xbillCard()
    }
}

#Preview {
    HomeView(vm: HomeViewModel())
}
