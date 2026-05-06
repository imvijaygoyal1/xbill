//
//  XBillArchivedRow.swift
//  xBill
//

import SwiftUI

struct XBillArchivedRow: View {
    let icon: String
    let title: String
    var subtitle: String?
    var isExpanded = false

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
                if let subtitle {
                    Text(subtitle)
                        .font(.appCaption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            Spacer(minLength: AppSpacing.sm)

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.appCaptionMedium)
                .foregroundStyle(AppColors.textTertiary)
                .frame(width: AppSpacing.tapTarget, height: AppSpacing.tapTarget, alignment: .trailing)
        }
        .padding(AppSpacing.md)
        .frame(minHeight: AppSpacing.controlHeight)
        .background(AppColors.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: String {
        [title, subtitle, isExpanded ? "expanded" : "collapsed"]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

#Preview("Archived Row") {
    VStack(spacing: AppSpacing.md) {
        XBillArchivedRow(icon: "archivebox.fill", title: "Archived groups", subtitle: "2 groups", isExpanded: false)
        XBillArchivedRow(icon: "archivebox.fill", title: "Archived groups", subtitle: "2 groups", isExpanded: true)
    }
    .padding(AppSpacing.lg)
    .xbillScreenBackground()
}

#Preview("Archived Row Dark") {
    XBillArchivedRow(icon: "archivebox.fill", title: "Archived groups", subtitle: "2 groups", isExpanded: false)
        .padding(AppSpacing.lg)
        .xbillScreenBackground()
        .preferredColorScheme(.dark)
}
