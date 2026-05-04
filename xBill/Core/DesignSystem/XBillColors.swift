//
//  XBillColors.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

extension Color {

    // MARK: - Brand (fintech purple palette)
    static var brandPrimary: Color { AppColors.primary }
    static var brandAccent: Color { AppColors.success }
    static var brandSurface: Color { AppColors.surfaceSoft }
    static var brandDeep: Color { AppColors.primaryDark }

    // MARK: - Background hierarchy (soft lavender canvas)
    static var bgPrimary: Color { AppColors.background }
    static var bgSecondary: Color { AppColors.background }
    static var bgTertiary: Color { AppColors.surfaceSoft }
    static var bgCard: Color { AppColors.surface }

    // MARK: - Text
    static var textPrimary: Color { AppColors.textPrimary }
    static var textSecondary: Color { AppColors.textSecondary }
    static var textTertiary: Color { AppColors.textTertiary }
    static var textInverse: Color { AppColors.textInverse }

    // MARK: - Semantic money colors
    static var moneyPositive: Color { AppColors.moneyPositive }
    static var moneyNegative: Color { AppColors.moneyNegative }
    static var moneySettled: Color { AppColors.moneySettled }
    static var moneyTotal: Color { AppColors.moneyTotal }

    // MARK: - Semantic money backgrounds
    static var moneyPositiveBg: Color { AppColors.moneyPositiveBg }
    static var moneyNegativeBg: Color { AppColors.moneyNegativeBg }
    static var moneySettledBg: Color { AppColors.moneySettledBg }

    // MARK: - UI chrome
    static var separator: Color { AppColors.border }
    static var tabBarBg: Color { AppColors.blackNav }
    static var navBarBg: Color { AppColors.background }
    static var inputBg: Color { AppColors.inputBackground }
    static var inputBorder: Color { AppColors.inputBorder }

    // MARK: - Category icon backgrounds
    static var catFood: Color { AppColors.adaptive(light: "#FFF0E8", dark: "#352820") }
    static var catTravel: Color { AppColors.surfaceSoft }
    static var catHome: Color { AppColors.moneyPositiveBg }
    static var catEntertain: Color { AppColors.moneyNegativeBg }
    static var catHealth: Color { AppColors.adaptive(light: "#E8F3FF", dark: "#1C2A3A") }
    static var catShopping: Color { AppColors.adaptive(light: "#FFF8E8", dark: "#332C1B") }
    static var catOther: Color { AppColors.moneySettledBg }

    // MARK: - Purple fintech swatch (direct hex — replaces old clay names)
    static var clayUbeLight: Color { AppColors.primaryLight }
    static var clayUbe: Color { AppColors.primary }
    static var clayUbeDark: Color { AppColors.primaryDark }

    // MARK: - Retained clay names mapped to new palette (backward compat)
    static var clayMatcha: Color { AppColors.success }
    static var clayMatchaLight: Color { AppColors.moneyPositiveBg }
    static var clayMatchaDark: Color { AppColors.success }
    static var claySlushie: Color { AppColors.primaryLight }
    static var claySlushieDark: Color { AppColors.primaryDark }
    static var clayLemonLight: Color { AppColors.warning.opacity(0.55) }
    static var clayLemon: Color { AppColors.warning }
    static var clayLemonDark: Color { AppColors.warning }
    static var clayPomegranate: Color { AppColors.error }
    static var clayBlueberry: Color { AppColors.blackNav }
    static var clayCanvas: Color { AppColors.background }
    static var clayOatBorder: Color { AppColors.border }
    static var clayOatLight: Color { AppColors.surfaceSoft }
    static var claySilver: Color { AppColors.textSecondary }
    static var clayCharcoal: Color { AppColors.textPrimary }
}
