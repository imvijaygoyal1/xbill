// AppShadow.swift — xBill Design System

import SwiftUI

enum AppShadow {
    static func card(colorScheme: ColorScheme) -> (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        colorScheme == .dark
            ? (.black.opacity(0.18), 8, 0, 4)
            : (.black.opacity(0.07), 12, 0, 4)
    }

    static func hero(colorScheme: ColorScheme) -> (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        colorScheme == .dark
            ? (AppColors.primary.opacity(0.28), 16, 0, 8)
            : (AppColors.primary.opacity(0.25), 20, 0, 8)
    }

    static func fab(colorScheme: ColorScheme) -> (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        colorScheme == .dark
            ? (AppColors.primary.opacity(0.45), 14, 0, 6)
            : (AppColors.primary.opacity(0.40), 12, 0, 6)
    }
}

extension View {
    func appCardShadow() -> some View {
        shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 4)
    }

    func appHeroShadow() -> some View {
        shadow(color: AppColors.primary.opacity(0.25), radius: 20, x: 0, y: 8)
    }

    func appFABShadow() -> some View {
        shadow(color: AppColors.primary.opacity(0.40), radius: 12, x: 0, y: 6)
    }
}
