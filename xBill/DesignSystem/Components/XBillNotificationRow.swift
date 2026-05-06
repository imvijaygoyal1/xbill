//
//  XBillNotificationRow.swift
//  xBill
//

import SwiftUI

struct XBillNotificationRow: View {
    let item: NotificationItem
    var isUnread = false
    var showsChevron = false

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            unreadIndicator

            notificationIcon

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(item.title)
                    .font(isUnread ? .appTitle : .appBody)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)

                Text(item.subtitle)
                    .font(.appCaption)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)

                Text(item.createdAt, format: .relative(presentation: .named))
                    .font(.appCaption)
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer(minLength: AppSpacing.sm)

            VStack(alignment: .trailing, spacing: AppSpacing.sm) {
                AmountBadge(amount: item.amount, direction: badgeDirection, currency: item.currency)

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.appCaptionMedium)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
        .frame(minHeight: AppSpacing.tapTarget)
        .xbillCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var unreadIndicator: some View {
        Circle()
            .fill(AppColors.primary.opacity(isUnread ? 1 : 0))
            .frame(width: AppSpacing.sm, height: AppSpacing.sm)
            .padding(.top, AppSpacing.md)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var notificationIcon: some View {
        switch item.eventType {
        case .expenseAdded:
            XBillCategoryIcon(category: item.category)
        case .settlementMade:
            Image(systemName: "checkmark.circle.fill")
                .font(.appIcon)
                .foregroundStyle(AppColors.success)
                .frame(width: XBillIcon.categorySize, height: XBillIcon.categorySize)
                .background(AppColors.moneySettledBg)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private var badgeDirection: AmountDirection {
        switch item.eventType {
        case .expenseAdded: .total
        case .settlementMade: .settled
        }
    }

    private var accessibilityLabel: String {
        let status = isUnread ? "Unread. " : ""
        let amount = item.amount.formatted(currencyCode: item.currency)
        return "\(status)\(item.title), \(item.subtitle), \(amount), \(item.createdAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

#Preview("Notification Row") {
    XBillScreenBackground {
        VStack(spacing: AppSpacing.md) {
            XBillNotificationRow(
                item: NotificationItem(
                    id: UUID(),
                    eventType: .expenseAdded,
                    title: "Dinner at Mesa",
                    subtitle: "Lake Trio · Paid by Vijay",
                    amount: 86.40,
                    currency: "USD",
                    category: .food,
                    createdAt: Date()
                ),
                isUnread: true,
                showsChevron: true
            )
            XBillNotificationRow(
                item: NotificationItem(
                    id: UUID(),
                    eventType: .settlementMade,
                    title: "Alex settled up",
                    subtitle: "Roommates · Paid Vijay",
                    amount: 24.00,
                    currency: "USD",
                    category: .other,
                    createdAt: Date().addingTimeInterval(-3600)
                )
            )
        }
        .padding(AppSpacing.lg)
    }
}
