//
//  XBillColors.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

extension Color {

    // MARK: - Brand (maps to asset catalog — updated to clay palette)
    static let brandPrimary     = Color("BrandPrimary")   // Ube 800 #43089f
    static let brandAccent      = Color("BrandAccent")    // Matcha 600 #078a52
    static let brandSurface     = Color("BrandSurface")
    static let brandDeep        = Color("BrandDeep")

    // MARK: - Background hierarchy (clay canvas)
    static let bgPrimary        = Color("BgPrimary")      // white
    static let bgSecondary      = Color("BgSecondary")    // warm cream #faf9f7
    static let bgTertiary       = Color("BgTertiary")
    static let bgCard           = Color("BgCard")         // white card surface

    // MARK: - Text (clay: black / warm silver)
    static let textPrimary      = Color("TextPrimary")    // Clay Black #000000
    static let textSecondary    = Color("TextSecondary")  // Warm Silver #9f9b93
    static let textTertiary     = Color("TextTertiary")
    static let textInverse      = Color("TextInverse")

    // MARK: - Semantic money colors (clay swatch mapped)
    static let moneyPositive    = Color("MoneyPositive")  // Matcha 600 #078a52
    static let moneyNegative    = Color("MoneyNegative")  // Pomegranate 400 #fc7981
    static let moneySettled     = Color("MoneySettled")   // Warm Silver #9f9b93
    static let moneyTotal       = Color("MoneyTotal")

    // MARK: - Semantic money backgrounds
    static let moneyPositiveBg  = Color("MoneyPositiveBg")
    static let moneyNegativeBg  = Color("MoneyNegativeBg")
    static let moneySettledBg   = Color("MoneySettledBg")

    // MARK: - UI chrome (clay: oat borders)
    static let separator        = Color("Separator")      // Oat Border #dad4c8
    static let tabBarBg         = Color("TabBarBg")
    static let navBarBg         = Color("NavBarBg")
    static let inputBg          = Color("InputBg")        // warm cream #faf9f7
    static let inputBorder      = Color("InputBorder")    // #717989

    // MARK: - Category icon backgrounds
    static let catFood          = Color("CatFood")
    static let catTravel        = Color("CatTravel")
    static let catHome          = Color("CatHome")
    static let catEntertain     = Color("CatEntertain")
    static let catHealth        = Color("CatHealth")
    static let catShopping      = Color("CatShopping")
    static let catOther         = Color("CatOther")

    // MARK: - Clay Swatch Palette (named, direct hex)
    // Matcha (Green)
    static let clayMatchaLight  = Color(hex: "#84e7a5")  // Matcha 300
    static let clayMatcha       = Color(hex: "#078a52")  // Matcha 600 — primary green
    static let clayMatchaDark   = Color(hex: "#02492a")  // Matcha 800

    // Slushie (Cyan)
    static let claySlushie      = Color(hex: "#3bd3fd")  // Slushie 500
    static let claySlushieDark  = Color(hex: "#0089ad")  // Slushie 800

    // Lemon (Gold)
    static let clayLemonLight   = Color(hex: "#f8cc65")  // Lemon 400
    static let clayLemon        = Color(hex: "#fbbd41")  // Lemon 500 — primary gold
    static let clayLemonDark    = Color(hex: "#d08a11")  // Lemon 700

    // Ube (Purple)
    static let clayUbeLight     = Color(hex: "#c1b0ff")  // Ube 300 — soft lavender
    static let clayUbe          = Color(hex: "#43089f")  // Ube 800 — primary purple
    static let clayUbeDark      = Color(hex: "#32037d")  // Ube 900

    // Pomegranate (Pink)
    static let clayPomegranate  = Color(hex: "#fc7981")  // Pomegranate 400

    // Blueberry (Navy)
    static let clayBlueberry    = Color(hex: "#01418d")  // Blueberry 800

    // MARK: - Clay Neutrals
    static let clayCanvas       = Color(hex: "#faf9f7")  // Warm Cream — the canvas
    static let clayOatBorder    = Color(hex: "#dad4c8")  // Oat Border
    static let clayOatLight     = Color(hex: "#eee9df")  // Oat Light (secondary border)
    static let claySilver       = Color(hex: "#9f9b93")  // Warm Silver — secondary text
    static let clayCharcoal     = Color(hex: "#55534e")  // Warm Charcoal — tertiary text
}
