//
//  XBillEmptyState.swift
//  xBill
//

import SwiftUI

struct XBillEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionLabel: String?
    var action: (() -> Void)?
    var illustration: XBillEmptyStateIllustration.Kind? = nil

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            XBillEmptyStateIllustration(kind: illustration ?? defaultIllustration, size: 112)
            VStack(spacing: AppSpacing.xs) {
                Text(title)
                    .font(.appH2)
                    .foregroundStyle(AppColors.textPrimary)
                Text(message)
                    .font(.appBody)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let actionLabel, let action {
                XBillPrimaryButton(title: actionLabel, action: action)
                    .padding(.top, AppSpacing.sm)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.xl)
    }

    private var defaultIllustration: XBillEmptyStateIllustration.Kind {
        if icon.contains("person") { return .friends }
        if icon.contains("bell") { return .notifications }
        if icon.contains("receipt") { return .expenses }
        if icon.contains("magnifyingglass") { return .search }
        if icon.contains("checkmark") { return .generic("checkmark.circle.fill") }
        return .generic(icon)
    }
}
