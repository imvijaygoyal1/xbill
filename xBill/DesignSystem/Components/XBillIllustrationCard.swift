//
//  XBillIllustrationCard.swift
//  xBill
//

import SwiftUI

struct XBillIllustrationCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shadow = AppShadow.card(colorScheme: colorScheme)

        content()
            .frame(maxWidth: .infinity)
            .padding(AppSpacing.lg)
            .background(AppColors.surfaceSoft)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                    .stroke(AppColors.border, lineWidth: 1)
            )
            .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

#Preview("Illustration Card") {
    XBillScreenBackground {
        XBillIllustrationCard {
            XBillFriendsIllustration(size: 200)
        }
        .padding(AppSpacing.lg)
    }
}
