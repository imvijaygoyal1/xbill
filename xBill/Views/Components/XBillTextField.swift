//
//  XBillTextField.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct XBillTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false
    /// Pass `focusedField == .thisField` from the caller's @FocusState.
    /// Keeping focus tracking in one place prevents dual-@FocusState conflicts
    /// that cause layout jumps when the keyboard appears.
    var isFocused: Bool = false

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
            }
        }
        .font(.appBody)
        .foregroundStyle(AppColors.textPrimary)
        .padding(.horizontal, AppSpacing.md)
        .frame(minHeight: AppSpacing.controlHeight)
        .background(AppColors.inputBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(
                    isFocused ? AppColors.primary : AppColors.inputBorder,
                    lineWidth: 1.5  // constant — only color animates, no geometry change
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

#Preview {
    @Previewable @State var text = ""
    VStack(spacing: 12) {
        XBillTextField(placeholder: "What was it for?", text: $text)
        XBillTextField(placeholder: "Email", text: $text, keyboardType: .emailAddress)
        XBillTextField(placeholder: "Password", text: $text, isSecure: true)
        XBillTextField(placeholder: "Focused example", text: $text, isFocused: true)
    }
    .padding()
    .background(AppColors.background)
}
