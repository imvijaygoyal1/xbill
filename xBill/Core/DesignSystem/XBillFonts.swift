import SwiftUI

// MARK: - Font tokens
// Headlines / UI text: SF Pro Rounded (system default + rounded design)
// Currency amounts:    SF Mono (tabular figures, decimal alignment)
// All tokens use Dynamic Type text styles so they scale with accessibility settings.

extension Font {

    // MARK: - Display (balance screens, hero numbers)
    // Uses Dynamic Type text styles → scales automatically with user's preferred text size.
    static let xbillHeroAmount   = Font.system(.largeTitle,   design: .monospaced, weight: .bold)
    static let xbillLargeAmount  = Font.system(.title,        design: .monospaced, weight: .bold)
    static let xbillMediumAmount = Font.system(.title3,       design: .monospaced, weight: .semibold)
    static let xbillSmallAmount  = Font.system(.subheadline,  design: .monospaced, weight: .medium)

    // MARK: - Navigation & Screen titles (rounded for modern feel)
    static let xbillNavTitle     = Font.system(.headline,    design: .rounded, weight: .semibold)
    static let xbillLargeTitle   = Font.system(.title,       design: .rounded, weight: .bold)
    static let xbillSectionTitle = Font.system(.footnote,    design: .rounded, weight: .semibold)

    // MARK: - Body (rounded for modern feel)
    static let xbillBodyLarge    = Font.system(.body,        design: .rounded)
    static let xbillBodyMedium   = Font.system(.subheadline, design: .rounded)
    static let xbillBodySmall    = Font.system(.footnote,    design: .rounded)

    // MARK: - Labels & metadata (rounded; apply .tracking(1.0) on metadata Text for professional spacing)
    static let xbillLabel        = Font.system(.footnote,    design: .rounded, weight: .medium)
    static let xbillCaption      = Font.system(.caption2,    design: .rounded)
    static let xbillCaptionBold  = Font.system(.caption2,    design: .rounded, weight: .semibold)

    // MARK: - Buttons (rounded for modern feel)
    static let xbillButtonLarge  = Font.system(.headline,    design: .rounded, weight: .semibold)
    static let xbillButtonMedium = Font.system(.subheadline, design: .rounded, weight: .semibold)
    static let xbillButtonSmall  = Font.system(.footnote,    design: .rounded, weight: .medium)
}
