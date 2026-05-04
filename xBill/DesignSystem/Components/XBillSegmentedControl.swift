//
//  XBillSegmentedControl.swift
//  xBill
//

import SwiftUI

struct XBillSegmentedControl<Option: Hashable>: View {
    let options: [(Option, String)]
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(options, id: \.0) { option, label in
                Button {
                    selection = option
                    HapticManager.selection()
                } label: {
                    Text(label)
                        .font(.appCaptionMedium)
                        .foregroundStyle(selection == option ? AppColors.textInverse : AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: AppSpacing.tapTarget)
                        .background(selection == option ? AppColors.primary : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppSpacing.xs)
        .background(AppColors.surfaceSoft)
        .clipShape(Capsule())
    }
}
