// AppColors.swift — xBill Design System
// Canonical adaptive color tokens for the playful fintech redesign.

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum AppColors {
    static let primary      = Color(hex: "#6C35FF")
    static let primaryDark  = Color(hex: "#4B16D8")
    static let primaryLight = Color(hex: "#B79CFF")
    static let success      = Color(hex: "#2DBE8D")
    static let error        = Color(hex: "#FF5C5C")
    static let warning      = Color(hex: "#FF9F43")

    static let background    = adaptive(light: "#F7F3FF", dark: "#0F0D16")
    static let surface       = adaptive(light: "#FFFFFF", dark: "#1A1724")
    static let surfaceSoft   = adaptive(light: "#F1ECFF", dark: "#242033")
    static let textPrimary   = adaptive(light: "#111111", dark: "#FFFFFF")
    static let textSecondary = adaptive(light: "#77727F", dark: "#B9B3C9")
    static let textTertiary  = adaptive(light: "#A099AF", dark: "#8F88A3")
    static let textInverse   = Color.white
    static let border        = adaptive(light: "#E7E0F7", dark: "#332D45")
    static let blackNav      = adaptive(light: "#111111", dark: "#08070C")

    static let moneyPositive   = success
    static let moneyNegative   = error
    static let moneySettled    = textSecondary
    static let moneyTotal      = primary
    static let moneyPositiveBg = adaptive(light: "#E8F9F4", dark: "#16372F")
    static let moneyNegativeBg = adaptive(light: "#FFF0F0", dark: "#3B2027")
    static let moneySettledBg  = adaptive(light: "#F0EFF2", dark: "#242033")

    static let inputBackground = adaptive(light: "#FFFFFF", dark: "#1A1724")
    static let inputBorder     = adaptive(light: "#E7E0F7", dark: "#332D45")

    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#8B5CFF"), primary, primaryDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var inviteGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#B79CFF").opacity(0.3), Color(hex: "#6C35FF").opacity(0.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func heroGradient(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(hex: "#9B6CFF"), primary, Color(hex: "#3A13B8")]
                : [Color(hex: "#8B5CFF"), primary, primaryDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func adaptive(light: String, dark: String) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
        #else
        return Color(hex: light)
        #endif
    }
}
