//
//  XBillIconPickerGrid.swift
//  xBill
//

import SwiftUI

struct XBillIconPickerGrid: View {
    let icons: [String]
    @Binding var selectedIcon: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: AppSpacing.sm), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: AppSpacing.sm) {
            ForEach(icons, id: \.self) { icon in
                Button {
                    selectedIcon = icon
                    HapticManager.selection()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                            .fill(selectedIcon == icon ? AppColors.surfaceSoft : AppColors.surface)
                        XBillAvatarPlaceholder(name: icon, size: 36)
                    }
                    .frame(width: 56, height: 56)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                            .stroke(selectedIcon == icon ? AppColors.primary : AppColors.border, lineWidth: selectedIcon == icon ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)
                .frame(minWidth: AppSpacing.tapTarget, minHeight: AppSpacing.tapTarget)
            }
        }
    }
}
