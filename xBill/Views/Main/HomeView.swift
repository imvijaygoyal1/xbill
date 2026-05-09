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
        .task { await vm.startRealtimeUpdates() }
        .errorAlert(item: $vm.errorAlert)
    }

    // MARK: - Content

    @ViewBuilder
    private var scrollContent: some View {
        if vm.isLoading && vm.groups.isEmpty {
            LoadingOverlay(message: "Loading groups…")
        } else if vm.groups.isEmpty {
            XBillScreenContainer(bottomPadding: AppSpacing.floatingActionBottomPadding) {
                HomeHeader(user: vm.currentUser, balance: vm.netBalance)
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
                    HomeHeader(user: vm.currentUser, balance: vm.netBalance)
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.top, AppSpacing.sm)

                    BalanceHeroCard(
                        label: vm.netBalance == .zero ? "All settled" : vm.netBalance > .zero ? "Net balance owed to you" : "Net balance you owe",
                        amount: abs(vm.netBalance),
                        subtitle: "\(vm.groups.count) group\(vm.groups.count == 1 ? "" : "s")",
                        isPositive: vm.netBalance >= .zero
                    )
                    .padding(.horizontal, AppSpacing.lg)

                    HStack(spacing: AppSpacing.sm) {
                        XBillMetricCard(
                            title: "Owed to you",
                            amount: vm.totalOwed,
                            icon: "arrow.down.left.circle.fill",
                            direction: .positive
                        )
                        XBillMetricCard(
                            title: "You owe",
                            amount: vm.totalOwing,
                            icon: "arrow.up.right.circle.fill",
                            direction: .negative
                        )
                    }
                    .padding(.horizontal, AppSpacing.lg)

                    XBillActionCard(
                        icon: "person.2.badge.plus",
                        title: "Invite friends",
                        subtitle: "Create a group and add people to split expenses"
                    ) {
                        showCreateGroup = true
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

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppSpacing.sm) {
                                ForEach(vm.groups) { group in
                                    NavigationLink(value: group) {
                                        GroupChipView(group: group)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, AppSpacing.lg)
                        }
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
                }
            }
        }
    }
}

#Preview {
    HomeView(vm: HomeViewModel())
}
