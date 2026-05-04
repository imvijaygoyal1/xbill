//
//  XBillCardModifier.swift
//  xBill
//

import SwiftUI

private struct XBillCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var padding: CGFloat

    func body(content: Content) -> some View {
        let shadow = AppShadow.card(colorScheme: colorScheme)
        content
            .padding(padding)
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .stroke(AppColors.border, lineWidth: 1)
            )
            .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

extension View {
    func xbillCard(padding: CGFloat = AppSpacing.md) -> some View {
        modifier(XBillCardModifier(padding: padding))
    }
}
