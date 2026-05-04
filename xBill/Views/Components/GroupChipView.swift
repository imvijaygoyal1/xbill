//
//  GroupChipView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct GroupChipView: View {
    let group: BillGroup

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                XBillAvatarPlaceholder(name: group.emoji, size: AppSpacing.tapTarget)
                Spacer(minLength: AppSpacing.sm)
                XBillStatusChip(text: group.currency, icon: "dollarsign.circle.fill", color: AppColors.primary)
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(group.name)
                    .font(.appTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Text(group.isArchived ? "Archived group" : "Active group")
                    .font(.appCaption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "calendar")
                    .font(.appCaption)
                    .foregroundStyle(AppColors.textTertiary)
                Text(group.createdAt.shortFormatted)
                    .font(.appCaption)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .frame(width: 184, alignment: .leading)
        .frame(minHeight: 168, alignment: .topLeading)
        .xbillCard(padding: AppSpacing.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(group.name) group, \(group.currency), \(group.isArchived ? "archived" : "active")")
        .accessibilityAddTraits(.isButton)
    }
}
