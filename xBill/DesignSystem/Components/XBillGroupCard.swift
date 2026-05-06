//
//  XBillGroupCard.swift
//  xBill
//

import SwiftUI

struct XBillGroupCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let group: BillGroup
    var subtitle: String?
    var trailing: String?
    var avatarUsers: [User]?
    var balanceLabel: String?
    var balanceAmount: Decimal?
    var balanceDirection: AmountDirection = .settled
    var showsChevron = true

    var body: some View {
        let shadow = AppShadow.card(colorScheme: colorScheme)

        HStack(alignment: .center, spacing: AppSpacing.md) {
            XBillAvatarPlaceholder(name: group.emoji, size: AppSpacing.xxl)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(group.name)
                        .font(.appTitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(subtitle ?? "\(group.currency) · \(group.createdAt.shortFormatted)")
                        .font(.appCaption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(2)
                }

                HStack(spacing: AppSpacing.sm) {
                    XBillStatusChip(
                        text: group.isArchived ? "Archived" : "Active",
                        icon: group.isArchived ? "archivebox.fill" : "checkmark.circle.fill",
                        color: group.isArchived ? AppColors.textSecondary : AppColors.primary
                    )

                    if let avatarUsers {
                        XBillAvatarStack(users: avatarUsers, maxVisible: 3, size: 28)
                    }
                }
            }

            Spacer(minLength: AppSpacing.sm)

            VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                if let balanceLabel, let balanceAmount {
                    Text(balanceLabel)
                        .font(.appCaption)
                        .foregroundStyle(AppColors.textSecondary)
                    Text(balanceAmount.formatted(currencyCode: group.currency))
                        .font(.appCaptionMedium)
                        .foregroundStyle(balanceColor)
                        .monospacedDigit()
                } else if let trailing {
                    Text(trailing)
                        .font(.appCaptionMedium)
                        .foregroundStyle(AppColors.textSecondary)
                }

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.appCaptionMedium)
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(width: AppSpacing.tapTarget, height: AppSpacing.tapTarget, alignment: .trailing)
                }
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 112)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xxl, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
        .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var balanceColor: Color {
        switch balanceDirection {
        case .positive:
            AppColors.moneyPositive
        case .negative:
            AppColors.moneyNegative
        case .settled:
            AppColors.moneySettled
        case .total:
            AppColors.moneyTotal
        }
    }

    private var accessibilityText: String {
        var parts = [
            "\(group.name) group",
            group.isArchived ? "archived" : "active",
            group.currency
        ]
        if let balanceLabel, let balanceAmount {
            parts.append("\(balanceLabel) \(balanceAmount.formatted(currencyCode: group.currency))")
        }
        return parts.joined(separator: ", ")
    }
}

#Preview("Group Card") {
    VStack(spacing: AppSpacing.md) {
        XBillGroupCard(
            group: PreviewData.groups[0],
            subtitle: "USD · \(PreviewData.groups[0].createdAt.shortFormatted)",
            avatarUsers: PreviewData.friends,
            balanceLabel: "Owed",
            balanceAmount: 42.50,
            balanceDirection: .positive
        )
        XBillGroupCard(
            group: BillGroup(
                id: UUID(),
                name: "Archived Trip",
                emoji: "🏝️",
                createdBy: PreviewData.currentUser.id,
                isArchived: true,
                currency: "USD",
                createdAt: .now
            ),
            subtitle: "USD · Apr 30, 2026",
            trailing: "Archived"
        )
    }
    .padding(AppSpacing.lg)
    .xbillScreenBackground()
}

#Preview("Group Card Dark") {
    XBillGroupCard(
        group: PreviewData.groups[1],
        subtitle: "USD · \(PreviewData.groups[1].createdAt.shortFormatted)",
        avatarUsers: PreviewData.friends,
        balanceLabel: "You owe",
        balanceAmount: 18.20,
        balanceDirection: .negative
    )
    .padding(AppSpacing.lg)
    .xbillScreenBackground()
    .preferredColorScheme(.dark)
}
