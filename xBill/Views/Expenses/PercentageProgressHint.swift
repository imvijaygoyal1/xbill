//
//  PercentageProgressHint.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  "Split by percentage works but the input style is not very intuitive."
//
//  The only feedback was `validationError` — *"Percentages must add up to 100. Currently: 65.00"* —
//  which arrives as a failure, states the wrong number (what you have used, not what is left), and
//  makes the user do the subtraction. This says what remains, and reads as progress.
//
//  Shared by the create form and the edit sheet, like `SplitParticipantRow`. Two copies of a split
//  control is how the edit sheet came to be missing three of its four inputs.
//

import SwiftUI

struct PercentageProgressHint: View {
    let progress: SplitEditor.PercentageProgress

    var body: some View {
        Label {
            Text(message)
        } icon: {
            Image(systemName: icon)
        }
        .font(.xbillCaption)
        .foregroundStyle(tint)
        .accessibilityIdentifier("xBill.split.percentHint")
    }

    private var message: String {
        if progress.isComplete { return "All 100% assigned" }
        if progress.isOver {
            return "\(Self.number(-progress.remaining))% over — remove some"
        }
        return "\(Self.number(progress.remaining))% left to assign"
    }

    private var icon: String {
        progress.isComplete ? "checkmark.circle.fill"
            : progress.isOver ? "exclamationmark.triangle.fill" : "circle.dashed"
    }

    /// Over-allocation is a problem; under-allocation is just unfinished work and should not be
    /// coloured like an error while the user is still typing.
    private var tint: Color {
        progress.isComplete ? Color.moneyPositive
            : progress.isOver ? Color.moneyNegative : Color.textSecondary
    }

    /// Trailing zeros are noise: "25% left", not "25.00% left".
    static func number(_ value: Decimal) -> String {
        var v = value, rounded = Decimal()
        NSDecimalRound(&rounded, &v, 2, .bankers)
        let s = "\(rounded)"
        return s.hasSuffix(".00") ? String(s.dropLast(3)) : s
    }
}
