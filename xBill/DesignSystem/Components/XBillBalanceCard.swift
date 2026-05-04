//
//  XBillBalanceCard.swift
//  xBill
//

import SwiftUI

struct XBillBalanceCard: View {
    let title: String
    let amount: Decimal
    let subtitle: String
    var currency: String = "USD"

    var body: some View {
        XBillHeroCard {
            HStack(spacing: AppSpacing.md) {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text(title.uppercased())
                        .font(.appCaptionMedium)
                        .tracking(1.08)
                        .foregroundStyle(AppColors.primaryLight)
                    Text(amount.formatted(currencyCode: currency))
                        .font(.appAmount)
                        .foregroundStyle(AppColors.textInverse)
                        .monospacedDigit()
                    Text(subtitle)
                        .font(.appCaption)
                        .foregroundStyle(AppColors.textInverse.opacity(0.82))
                }
                Spacer(minLength: AppSpacing.sm)
                XBillWalletIllustration(size: 72)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(amount.formatted(currencyCode: currency)), \(subtitle)")
    }
}
