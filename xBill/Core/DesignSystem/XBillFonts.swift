import SwiftUI

// MARK: - Font tokens
// Headlines / UI text: SF Pro (system default)
// Currency amounts:    SF Mono (tabular figures, decimal alignment)

extension Font {

    // MARK: - Display (balance screens, hero numbers)
    static let xbillHeroAmount   = Font.system(size: 40, weight: .bold,    design: .monospaced)
    static let xbillLargeAmount  = Font.system(size: 28, weight: .bold,    design: .monospaced)
    static let xbillMediumAmount = Font.system(size: 20, weight: .semibold, design: .monospaced)
    static let xbillSmallAmount  = Font.system(size: 15, weight: .medium,  design: .monospaced)

    // MARK: - Navigation & Screen titles
    static let xbillNavTitle     = Font.system(size: 17, weight: .semibold, design: .default)
    static let xbillLargeTitle   = Font.system(size: 28, weight: .bold,    design: .default)
    static let xbillSectionTitle = Font.system(size: 13, weight: .semibold, design: .default)

    // MARK: - Body
    static let xbillBodyLarge    = Font.system(size: 17, weight: .regular, design: .default)
    static let xbillBodyMedium   = Font.system(size: 15, weight: .regular, design: .default)
    static let xbillBodySmall    = Font.system(size: 13, weight: .regular, design: .default)

    // MARK: - Labels & metadata
    static let xbillLabel        = Font.system(size: 13, weight: .medium,  design: .default)
    static let xbillCaption      = Font.system(size: 11, weight: .regular, design: .default)
    static let xbillCaptionBold  = Font.system(size: 11, weight: .semibold, design: .default)

    // MARK: - Buttons
    static let xbillButtonLarge  = Font.system(size: 17, weight: .semibold, design: .default)
    static let xbillButtonMedium = Font.system(size: 15, weight: .semibold, design: .default)
    static let xbillButtonSmall  = Font.system(size: 13, weight: .medium,  design: .default)
}
