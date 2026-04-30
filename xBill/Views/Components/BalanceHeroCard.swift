//
//  BalanceHeroCard.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct BalanceHeroCard: View {
    let label: String
    let amount: Decimal
    let subtitle: String
    var currency: String = "USD"
    var isPositive: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: XBillSpacing.xs) {
            Text(label.uppercased())
                .font(.xbillUpperLabel)
                .tracking(1.08)
                .foregroundStyle(Color.brandAccent)

            Text(amount.formatted(currencyCode: currency))
                .font(.xbillHeroAmount)
                .foregroundStyle(Color.textInverse)
                .contentTransition(.numericText())

            Text(subtitle)
                .font(.xbillCaption)
                .foregroundStyle(Color.brandAccent.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, XBillSpacing.xl)
        .padding(.vertical, XBillSpacing.lg)
        .background(Color.brandPrimary)
        .clipShape(RoundedRectangle(cornerRadius: XBillRadius.card))
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
