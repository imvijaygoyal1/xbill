//
//  XBillFloatingAddButton.swift
//  xBill
//

import SwiftUI

struct XBillFloatingAddButton: View {
    @Environment(\.colorScheme) private var colorScheme
    var systemImage = "plus"
    let action: () -> Void

    var body: some View {
        let shadow = AppShadow.fab(colorScheme: colorScheme)
        Button {
            HapticManager.impact(.medium)
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.appH2)
                .foregroundStyle(AppColors.textInverse)
                .frame(width: 60, height: 60)
                .background(AppColors.primary)
                .clipShape(Circle())
                .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add")
    }
}
