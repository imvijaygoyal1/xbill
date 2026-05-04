//
//  XBillHeroCard.swift
//  xBill
//

import SwiftUI

struct XBillHeroCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(AppSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppGradient.hero(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous))
            .shadow(
                color: AppShadow.hero(colorScheme: colorScheme).color,
                radius: AppShadow.hero(colorScheme: colorScheme).radius,
                x: AppShadow.hero(colorScheme: colorScheme).x,
                y: AppShadow.hero(colorScheme: colorScheme).y
            )
    }
}
