//
//  XBillActionCard.swift
//  xBill
//

import SwiftUI

struct XBillActionCard: View {
    let icon: String
    let title: String
    let subtitle: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(.appIcon)
                    .foregroundStyle(AppColors.primary)
                    .frame(width: AppSpacing.tapTarget, height: AppSpacing.tapTarget)
                    .background(AppColors.surfaceSoft)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(title)
                        .font(.appTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.appCaption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.appCaptionMedium)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .frame(minHeight: 64)
        }
        .buttonStyle(.plain)
        .xbillCard()
    }
}
