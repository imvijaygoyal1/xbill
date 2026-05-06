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
    var secondaryActionLabel: String?
    var secondaryAction: (() -> Void)?
    var illustration: XBillEmptyStateIllustration.Kind? = nil
    var showsIllustration = true
    var illustrationAccessibilityLabel: String?

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            if showsIllustration {
                XBillIllustrationCard {
                    XBillEmptyStateIllustration(kind: illustration ?? defaultIllustration, size: 200)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(illustrationAccessibilityLabel ?? "Empty state illustration")
                .accessibilityHidden(illustrationAccessibilityLabel == nil)
            }

            VStack(spacing: AppSpacing.sm) {
                Text(title)
                    .font(.appH2)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.appBody)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if let actionLabel, let action {
                VStack(spacing: AppSpacing.sm) {
                    XBillPrimaryButton(title: actionLabel, action: action)
                    if let secondaryActionLabel, let secondaryAction {
                        XBillSecondaryButton(title: secondaryActionLabel, action: secondaryAction)
                    }
                }
                .padding(.top, AppSpacing.sm)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
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

#Preview("Empty State") {
    XBillScreenBackground {
        XBillEmptyState(
            icon: "person.2.fill",
            title: "No Friends Yet",
            message: "Add friends to track IOUs or split expenses outside of groups.",
            actionLabel: "Add Friend",
            action: {},
            illustration: .friends
        )
        .padding(AppSpacing.lg)
    }
}

#Preview("Empty State Dark") {
    XBillScreenBackground {
        XBillEmptyState(
            icon: "person.2.fill",
            title: "No Friends Yet",
            message: "Add friends to track IOUs or split expenses outside of groups.",
            actionLabel: "Add Friend",
            action: {},
            illustration: .friends
        )
        .padding(AppSpacing.lg)
    }
    .preferredColorScheme(.dark)
}
