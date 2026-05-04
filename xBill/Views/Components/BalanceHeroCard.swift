//
//  BalanceHeroCard.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct BalanceHeroCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    let amount: Decimal
    let subtitle: String
    var currency: String = "USD"
    var isPositive: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(label.uppercased())
                    .font(.appCaptionMedium)
                    .tracking(1.08)
                    .foregroundStyle(AppColors.primaryLight)

                Text(amount.formatted(currencyCode: currency))
                    .font(.appAmount)
                    .foregroundStyle(AppColors.textInverse)
                    .contentTransition(.numericText())

                Text(subtitle)
                    .font(.appCaption)
                    .foregroundStyle(AppColors.textInverse.opacity(0.82))
            }
            Spacer(minLength: AppSpacing.sm)
            XBillWalletIllustration(size: 72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
        .background(AppGradient.hero(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(amount.formatted(currencyCode: currency)), \(subtitle)")
    }
}

#Preview {
    VStack(spacing: 12) {
        BalanceHeroCard(label: "You are owed", amount: 124.50, subtitle: "across 3 groups", isPositive: true)
        BalanceHeroCard(label: "You owe", amount: 42.00, subtitle: "in 1 group", isPositive: false)
    }
    .padding()
}
