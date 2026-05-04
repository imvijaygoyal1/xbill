//
//  XBillGroupCard.swift
//  xBill
//

import SwiftUI

struct XBillGroupCard: View {
    let group: BillGroup
    var subtitle: String?
    var trailing: String?

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            XBillAvatarPlaceholder(name: group.emoji, size: AppSpacing.xxl)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(group.name)
                    .font(.appTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text(subtitle ?? "\(group.currency) · \(group.createdAt.shortFormatted)")
                    .font(.appCaption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.appCaptionMedium)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .frame(minHeight: AppSpacing.tapTarget)
        .xbillCard()
    }
}
