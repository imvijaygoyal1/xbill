//
//  XBillFonts.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

// MARK: - Font tokens
// Clay weight hierarchy: 600 (headings) / 500 (UI) / 400 (body)
// System font with .rounded design approximates Roobert's geometric character.
// All tokens use Dynamic Type text styles so they scale with accessibility settings.
// Monospace tokens (amounts) use .monospaced design for tabular figures.

extension Font {

    // MARK: - Display amounts (balance screens, hero numbers)
    static let xbillHeroAmount   = Font.system(.largeTitle,   design: .monospaced, weight: .bold)      // 600 equiv
    static let xbillLargeAmount  = Font.system(.title,        design: .monospaced, weight: .bold)
    static let xbillMediumAmount = Font.system(.title3,       design: .monospaced, weight: .semibold)
    static let xbillSmallAmount  = Font.system(.subheadline,  design: .monospaced, weight: .medium)    // 500

    // MARK: - Headings (clay: weight 600, tight tracking at large sizes)
    static let xbillNavTitle     = Font.system(.headline,    design: .rounded, weight: .bold)           // 600
    static let xbillLargeTitle   = Font.system(.title,       design: .rounded, weight: .bold)           // 600
    static let xbillSectionTitle = Font.system(.footnote,    design: .rounded, weight: .semibold)       // 600

    // MARK: - Body (clay: weight 400, generous line-height via SwiftUI defaults)
    static let xbillBodyLarge    = Font.system(.body,        design: .rounded, weight: .regular)        // 400
    static let xbillBodyMedium   = Font.system(.subheadline, design: .rounded, weight: .regular)        // 400
    static let xbillBodySmall    = Font.system(.footnote,    design: .rounded, weight: .regular)        // 400

    // MARK: - UI labels (clay: weight 500)
    static let xbillLabel        = Font.system(.footnote,    design: .rounded, weight: .medium)         // 500
    static let xbillCaption      = Font.system(.caption2,    design: .rounded, weight: .regular)        // 400
    static let xbillCaptionBold  = Font.system(.caption2,    design: .rounded, weight: .semibold)       // 600

    // MARK: - Uppercase labels (clay: weight 600, +tracking applied at call site via .tracking(1.08))
    static let xbillUpperLabel   = Font.system(.caption,     design: .rounded, weight: .semibold)       // 600

    // MARK: - Buttons (clay: weight 500)
    static let xbillButtonLarge  = Font.system(.headline,    design: .rounded, weight: .semibold)       // 600 for primary CTA
    static let xbillButtonMedium = Font.system(.subheadline, design: .rounded, weight: .medium)         // 500
    static let xbillButtonSmall  = Font.system(.footnote,    design: .rounded, weight: .medium)         // 500
}
