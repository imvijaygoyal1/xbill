//
//  AmountBadge.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

enum AmountDirection {
    case positive, negative, settled, total
}

struct AmountBadge: View {
    let amount: Decimal
    let direction: AmountDirection
    var currency: String = "USD"

    private var fg: Color {
        switch direction {
        case .positive: return .moneyPositive
        case .negative: return .moneyNegative
        case .settled:  return .moneySettled
        case .total:    return .moneyTotal
        }
    }
    private var bg: Color {
        switch direction {
        case .positive: return .moneyPositiveBg
        case .negative: return .moneyNegativeBg
        case .settled:  return .moneySettledBg
        case .total:    return .brandSurface
        }
    }
    private var prefix: String {
        switch direction {
        case .positive: return "+"
        case .negative: return "-"
        default: return ""
        }
    }

    private var accessibilityDescription: String {
        switch direction {
        case .positive: return "owed to you: \(amount.formatted(currencyCode: currency))"
        case .negative: return "you owe: \(amount.formatted(currencyCode: currency))"
        case .settled:  return "settled: \(amount.formatted(currencyCode: currency))"
        case .total:    return "total: \(amount.formatted(currencyCode: currency))"
        }
    }

    var body: some View {
        Text("\(prefix)\(amount.formatted(currencyCode: currency))")
            .font(.xbillSmallAmount)
            .foregroundStyle(fg)
            .padding(.horizontal, XBillSpacing.sm)
            .padding(.vertical, XBillSpacing.xs)
            .background(bg)
            .clipShape(Capsule())
            .accessibilityLabel(accessibilityDescription)
    }
}

#Preview {
    VStack(spacing: 8) {
        AmountBadge(amount: 42.50, direction: .positive)
        AmountBadge(amount: 17.00, direction: .negative)
        AmountBadge(amount: 0.00,  direction: .settled)
        AmountBadge(amount: 120.00, direction: .total)
    }
    .padding()
}
