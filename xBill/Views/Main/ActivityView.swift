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
                    loadingState
                } else if vm.items.isEmpty {
                    emptyState
                } else {
                    activityList
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(AppColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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

    private var loadingState: some View {
        XBillScreenContainer(mode: .fixed) {
            notificationsHeader
            Spacer()
            LoadingOverlay(message: "Loading activity…")
            Spacer()
        }
    }

    private var emptyState: some View {
        XBillScreenContainer(mode: .fixed, contentSpacing: AppSpacing.xl) {
            notificationsHeader
            Spacer()
            XBillEmptyState(
                icon: "bell.fill",
                title: "No Activity Yet",
                message: "New expenses and settlements across your groups will appear here.",
                illustration: .notifications,
                illustrationAccessibilityLabel: "No notifications"
            )
            Spacer()
        }
    }

    private var activityList: some View {
        XBillScrollView(spacing: AppSpacing.xl) {
            notificationsHeader

            ForEach(groupedItems, id: \.header) { section in
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    XBillSectionHeader(section.header)
                    ForEach(section.items) { item in
                        XBillNotificationRow(
                            item: item,
                            isUnread: item.createdAt > lastViewed
                        )
                    }
                }
            }
        }
        .background(AppColors.background.ignoresSafeArea())
    }

    private var notificationsHeader: some View {
        XBillScreenHeader(title: "Notifications") {
            if vm.hasUnread {
                Button {
                    HapticManager.selection()
                    vm.markAllRead()
                } label: {
                    Text("Mark All Read")
                        .font(.appCaptionMedium)
                        .foregroundStyle(AppColors.primary)
                        .frame(minHeight: AppSpacing.tapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark all notifications as read")
            }
        }
        .padding(.horizontal, -AppSpacing.lg)
    }
}

#Preview("Notifications") {
    ActivityView(vm: ActivityViewModel())
}

#Preview("Notifications Dark") {
    ActivityView(vm: ActivityViewModel())
        .preferredColorScheme(.dark)
}
