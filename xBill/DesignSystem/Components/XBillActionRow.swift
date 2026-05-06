//
//  XBillActionRow.swift
//  xBill
//

import SwiftUI

struct XBillActionRow: View {
    let icon: String
    let title: String
    var subtitle: String?
    var showsChevron = true

    var body: some View {
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
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.appCaption)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: AppSpacing.sm)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.appCaptionMedium)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .frame(minHeight: AppSpacing.tapTarget)
        .xbillCard()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subtitle == nil ? title : "\(title), \(subtitle ?? "")")
    }
}

#Preview("Action Row") {
    XBillScreenBackground {
        VStack(spacing: AppSpacing.md) {
            XBillActionRow(
                icon: "person.crop.circle.badge.plus",
                title: "Import from Contacts",
                subtitle: "Find people already using xBill"
            )
            XBillActionRow(
                icon: "square.and.arrow.up",
                title: "Share QR Link",
                subtitle: "Let friends add you directly"
            )
        }
        .padding(AppSpacing.lg)
    }
}
