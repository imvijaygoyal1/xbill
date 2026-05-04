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

    @FocusState private var isFocused: Bool

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
                    lineWidth: isFocused ? 1.5 : 1
                )
        )
        .focused($isFocused)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

#Preview {
    @Previewable @State var text = ""
    VStack(spacing: 12) {
        XBillTextField(placeholder: "What was it for?", text: $text)
        XBillTextField(placeholder: "Email", text: $text, keyboardType: .emailAddress)
        XBillTextField(placeholder: "Password", text: $text, isSecure: true)
    }
    .padding()
    .background(AppColors.background)
}
