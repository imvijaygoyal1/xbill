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
                    .foregroundStyle(AppColors.textSecondary)

                Text(amount.formatted(currencyCode: currency))
                    .font(.appAmount)
                    .foregroundStyle(isPositive ? AppColors.moneyPositive : AppColors.moneyNegative)
                    .contentTransition(.numericText())
                    .monospacedDigit()

                Text(subtitle)
                    .font(.appCaption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer(minLength: AppSpacing.sm)
            Image(systemName: isPositive ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(isPositive ? AppColors.moneyPositive : AppColors.moneyNegative)
                .frame(width: 56, height: 56)
                .background((isPositive ? AppColors.moneyPositiveBg : AppColors.moneyNegativeBg))
                .clipShape(Circle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.lg)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xxl, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
        .shadow(
            color: AppShadow.card(colorScheme: colorScheme).color,
            radius: AppShadow.card(colorScheme: colorScheme).radius,
            x: AppShadow.card(colorScheme: colorScheme).x,
            y: AppShadow.card(colorScheme: colorScheme).y
        )
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
