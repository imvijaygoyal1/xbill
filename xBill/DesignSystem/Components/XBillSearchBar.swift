//
//  XBillSearchBar.swift
//  xBill
//

import SwiftUI

struct XBillSearchBar: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColors.textSecondary)
            TextField(placeholder, text: $text)
                .font(.appBody)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel(placeholder)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColors.textTertiary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .foregroundStyle(AppColors.textPrimary)
        .frame(minHeight: AppSpacing.tapTarget)
        .padding(.horizontal, AppSpacing.md)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }
}

#Preview("Search Bar") {
    @Previewable @State var text = ""

    VStack {
        XBillSearchBar(placeholder: "Search groups", text: $text)
    }
    .padding(AppSpacing.lg)
    .xbillScreenBackground()
}

#Preview("Search Bar Dark") {
    @Previewable @State var text = "Lake"

    VStack {
        XBillSearchBar(placeholder: "Search groups", text: $text)
    }
    .padding(AppSpacing.lg)
    .xbillScreenBackground()
    .preferredColorScheme(.dark)
}
