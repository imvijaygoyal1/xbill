//
//  XBillSegmentedControl.swift
//  xBill
//

import SwiftUI

/// Glass only on the selected segment. An unselected segment must stay fully clear or the
/// track becomes glass-on-glass, which Apple's guidance calls out and which reads as mud.
private struct XBillSegmentSurface: ViewModifier {
    let isSelected: Bool
    func body(content: Content) -> some View {
        if isSelected {
            content.liquidGlassButton(tint: AppColors.primary, fallback: AppColors.primary, in: Capsule())
        } else {
            content.background(Color.clear).clipShape(Capsule())
        }
    }
}

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
                        .modifier(XBillSegmentSurface(isSelected: selection == option))
                        // Same defect as XBillButtonBase: the label is centred `Text`, so without
                        // this only the text itself is tappable and the padding either side of a
                        // segment is inert.
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppSpacing.xs)
        .background(AppColors.surfaceSoft)
        .clipShape(Capsule())
    }
}
