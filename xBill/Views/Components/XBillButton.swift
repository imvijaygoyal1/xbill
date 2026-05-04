//
//  XBillButton.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

enum XBillButtonStyle {
    case primary
    case secondary
    case ghost
    case destructive
}

struct XBillButton: View {
    let title: String
    var style: XBillButtonStyle = .primary
    var isLoading: Bool = false
    let action: () -> Void

    private var bgColor: Color {
        switch style {
        case .primary:     return AppColors.primary
        case .secondary:   return .clear
        case .ghost:       return .clear
        case .destructive: return AppColors.error
        }
    }
    private var fgColor: Color {
        switch style {
        case .primary:     return AppColors.textInverse
        case .secondary:   return AppColors.primary
        case .ghost:       return AppColors.primary
        case .destructive: return AppColors.textInverse
        }
    }
    private var borderColor: Color {
        switch style {
        case .secondary: return AppColors.primary
        case .ghost:     return AppColors.border
        default:         return .clear
        }
    }
    private var cornerRadius: CGFloat {
        switch style {
        case .ghost: return AppRadius.sm
        default:     return AppRadius.md
        }
    }

    var body: some View {
        Button(action: {
            HapticManager.impact(.medium)
            action()
        }) {
            ZStack {
                if isLoading {
                    ProgressView().tint(fgColor)
                } else {
                    Text(title)
                        .font(.xbillButtonLarge)
                        .foregroundStyle(fgColor)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppSpacing.controlHeight)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

#Preview {
    VStack(spacing: 12) {
        XBillButton(title: "Add Expense", style: .primary) {}
        XBillButton(title: "Cancel", style: .secondary) {}
        XBillButton(title: "Sign out", style: .ghost) {}
        XBillButton(title: "Delete", style: .destructive) {}
        XBillButton(title: "Saving…", style: .primary, isLoading: true) {}
    }
    .padding()
}
