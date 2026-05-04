//
//  ActivityView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct ActivityView: View {
    @Bindable var vm: ActivityViewModel

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.items.isEmpty {
                    LoadingOverlay(message: "Loading activity…")
                } else if vm.items.isEmpty {
                    XBillScreenContainer {
                        XBillPageHeader(title: "Notifications")
                            .padding(.horizontal, -AppSpacing.lg)
                        XBillEmptyStateIllustration(kind: .notifications, size: 220)
                            .frame(maxWidth: .infinity)
                        EmptyStateView(
                            icon: "bell.fill",
                            title: "No Activity Yet",
                            message: "New expenses and settlements across your groups will appear here.",
                            illustration: .notifications
                        )
                    }
                } else {
                    activityList
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(AppColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                if vm.hasUnread {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Mark All Read") {
                            HapticManager.selection()
                            vm.markAllRead()
                        }
                        .font(.xbillCaption)
                        .foregroundStyle(Color.brandPrimary)
                    }
                }
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .onAppear {
                if vm.hasUnread { vm.markAllRead() }
            }
        }
        .errorAlert(item: $vm.errorAlert)
    }

    // MARK: - Grouped list

    private var lastViewed: Date { NotificationStore.shared.lastViewedAt() }

    private var groupedItems: [(header: String, items: [NotificationItem])] {
        let calendar = Calendar.current
        let grouped  = Dictionary(grouping: vm.items) { item -> String in
            if calendar.isDateInToday(item.createdAt)     { return "TODAY" }
            if calendar.isDateInYesterday(item.createdAt) { return "YESTERDAY" }
            return item.createdAt.shortFormatted.uppercased()
        }
        return grouped
            .map { (header: $0.key, items: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.items.first?.createdAt ?? .distantPast > $1.items.first?.createdAt ?? .distantPast }
    }

    private var activityList: some View {
        List {
            Section {
                XBillPageHeader(title: "Notifications") {
                    if vm.hasUnread {
                        Button("Mark All Read") {
                            HapticManager.selection()
                            vm.markAllRead()
                        }
                        .font(.appCaptionMedium)
                        .foregroundStyle(AppColors.primary)
                        .frame(minHeight: AppSpacing.tapTarget)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            ForEach(groupedItems, id: \.header) { section in
                Section {
                    ForEach(section.items) { item in
                        NotificationRowView(item: item, lastViewed: lastViewed)
                            .listRowBackground(Color.bgCard)
                    }
                } header: {
                    Text(section.header)
                        .font(.xbillCaptionBold)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .listRowSeparatorTint(AppColors.border)
    }
}

// MARK: - Notification Row

private struct NotificationRowView: View {
    let item: NotificationItem
    let lastViewed: Date

    private var isUnread: Bool { item.createdAt > lastViewed }

    var body: some View {
        HStack(alignment: .top, spacing: XBillSpacing.md) {
            Circle()
                .fill(isUnread ? Color.brandPrimary : Color.clear)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
                .accessibilityHidden(true)

            eventIcon

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(isUnread ? .xbillBodyMedium : .xbillBodyLarge)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                Text(item.subtitle)
                    .font(.xbillCaption)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)

                Text(item.createdAt, format: .relative(presentation: .named))
                    .font(.xbillCaption)
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()

            AmountBadge(amount: item.amount, direction: badgeDirection, currency: item.currency)
        }
        .padding(.vertical, XBillSpacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var eventIcon: some View {
        switch item.eventType {
        case .expenseAdded:
            CategoryIconView(category: item.category, size: XBillIcon.categorySize)
        case .settlementMade:
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.moneySettledBg)
                    .frame(width: XBillIcon.categorySize, height: XBillIcon.categorySize)
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.moneySettled)
                    .font(.system(size: 20))
            }
        }
    }

    private var badgeDirection: AmountDirection {
        switch item.eventType {
        case .expenseAdded:   return .total
        case .settlementMade: return .settled
        }
    }

    private var accessibilityLabel: String {
        let status = isUnread ? "Unread. " : ""
        let amountStr = item.amount.formatted(currencyCode: item.currency)
        return "\(status)\(item.title), \(item.subtitle), \(amountStr)"
    }
}

#Preview {
    ActivityView(vm: ActivityViewModel())
}
