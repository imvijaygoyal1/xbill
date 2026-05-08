//
//  ActivityView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct ActivityView: View {
    @Bindable var vm: ActivityViewModel
    @State private var selectedItem: NotificationItem?

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
            // .onAppear is intentionally omitted: .task already loads and sets unreadCount.
            // A separate .onAppear { refreshUnreadCount() } would trigger a second load
            // on first appear and a stale count refresh on every subsequent tab switch.
            .sheet(item: $selectedItem) { item in
                NotificationDetailSheet(
                    item: currentItem(for: item) ?? item,
                    isUnread: !(currentItem(for: item)?.isRead ?? item.isRead),
                    markRead: {
                        vm.markRead(item)
                        selectedItem = currentItem(for: item)
                    },
                    markUnread: {
                        vm.markUnread(item)
                        selectedItem = currentItem(for: item)
                    },
                    delete: {
                        vm.delete(item)
                        selectedItem = nil
                    }
                )
            }
        }
        .errorAlert(item: $vm.errorAlert)
    }

    // MARK: - Grouped list

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
                        notificationButton(for: item)
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

    private func notificationButton(for item: NotificationItem) -> some View {
        Button {
            HapticManager.selection()
            vm.markRead(item)
            selectedItem = currentItem(for: item) ?? item
        } label: {
            XBillNotificationRow(
                item: item,
                isUnread: !item.isRead,
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens notification details")
        .contextMenu {
            if item.isRead {
                Button {
                    vm.markUnread(item)
                } label: {
                    Label("Mark Unread", systemImage: "envelope.badge")
                }
            } else {
                Button {
                    vm.markRead(item)
                } label: {
                    Label("Mark Read", systemImage: "envelope.open")
                }
            }

            Button(role: .destructive) {
                vm.delete(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if item.isRead {
                Button {
                    vm.markUnread(item)
                } label: {
                    Label("Mark Unread", systemImage: "envelope.badge")
                }
                .tint(AppColors.primary)
            } else {
                Button {
                    vm.markRead(item)
                } label: {
                    Label("Mark Read", systemImage: "envelope.open")
                }
                .tint(AppColors.success)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                vm.delete(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func currentItem(for item: NotificationItem) -> NotificationItem? {
        vm.items.first { $0.id == item.id }
    }
}

private struct NotificationDetailSheet: View {
    let item: NotificationItem
    let isUnread: Bool
    let markRead: () -> Void
    let markUnread: () -> Void
    let delete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            XBillScreenContainer(
                horizontalPadding: AppSpacing.lg,
                contentSpacing: AppSpacing.xl,
                bottomPadding: AppSpacing.xl
            ) {
                XBillPageHeader(
                    title: "Alert Details",
                    subtitle: item.createdAt.formatted(date: .abbreviated, time: .shortened),
                    showsBackButton: true,
                    backAction: { dismiss() }
                )
                .padding(.horizontal, -AppSpacing.lg)

                XBillNotificationRow(item: item, isUnread: isUnread)

                detailSection

                VStack(spacing: AppSpacing.md) {
                    if isUnread {
                        XBillPrimaryButton(title: "Mark Read", icon: "envelope.open") {
                            markRead()
                        }
                    } else {
                        XBillSecondaryButton(title: "Mark Unread", icon: "envelope.badge") {
                            markUnread()
                        }
                    }

                    XBillSecondaryButton(title: "Delete Alert", icon: "trash") {
                        delete()
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            XBillSectionHeader("Details")
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                detailRow("Title", item.title)
                Divider().overlay(AppColors.border)
                detailRow("Context", item.subtitle)
                Divider().overlay(AppColors.border)
                detailRow("Amount", item.amount.formatted(currencyCode: item.currency))
                Divider().overlay(AppColors.border)
                detailRow("Status", isUnread ? "Unread" : "Read")
            }
            .xbillCard()
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.md) {
            Text(title)
                .font(.appCaptionMedium)
                .foregroundStyle(AppColors.textSecondary)
            Spacer(minLength: AppSpacing.md)
            Text(value)
                .font(.appBody)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview("Notifications") {
    ActivityView(vm: ActivityViewModel())
}

#Preview("Notifications Dark") {
    ActivityView(vm: ActivityViewModel())
        .preferredColorScheme(.dark)
}
