//
//  SplitSlider.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

/// A labeled slider for adjusting a split percentage (0–100).
struct SplitSlider: View {
    let label: String
    @Binding var percentage: Decimal
    var currency: String = "USD"
    var totalAmount: Decimal = .zero

    private var doubleBinding: Binding<Double> {
        Binding(
            get: { (percentage as NSDecimalNumber).doubleValue },
            set: { percentage = Decimal($0).rounded }
        )
    }

    private var computedAmount: Decimal {
        guard totalAmount > .zero else { return .zero }
        return (totalAmount * percentage / 100).rounded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(percentage, format: .number.precision(.fractionLength(0)))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                if totalAmount > .zero {
                    Text(computedAmount.formatted(currencyCode: currency))
                        .font(.subheadline.monospacedDigit().bold())
                        .foregroundStyle(.primary)
                        .frame(width: 72, alignment: .trailing)
                }
            }

            Slider(value: doubleBinding, in: 0...100, step: 1)
                .tint(.accentColor)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    @Previewable @State var pct: Decimal = 33
    return Form {
        SplitSlider(
            label: "Alice",
            percentage: $pct,
            currency: "USD",
            totalAmount: 90.00
        )
    }
}
