// AppTypography.swift — xBill Design System
// SF Pro type scale. Fixed visual sizes are scaled relative to Dynamic Type roles.

import SwiftUI

extension Font {
    static let appDisplay  = Font.system(size: 32, weight: .bold,     design: .default)
    static let appH1       = Font.system(size: 28, weight: .bold,     design: .default)
    static let appH2       = Font.system(size: 22, weight: .semibold, design: .default)
    static let appTitle    = Font.system(size: 17, weight: .semibold, design: .default)
    static let appBody     = Font.system(size: 15, weight: .regular,  design: .default)
    static let appCaption  = Font.system(size: 13, weight: .regular,  design: .default)
    static let appCaptionMedium = Font.system(.footnote, design: .default,   weight: .medium)
    static let appAmount   = Font.system(.largeTitle,    design: .monospaced, weight: .bold)
    static let appAmountSm = Font.system(.title3,        design: .monospaced, weight: .semibold)
    static let appIcon     = Font.system(size: 18, weight: .semibold, design: .default)
    static let appTabLabel = Font.system(size: 10, weight: .semibold, design: .default)
    static let appBadge    = Font.system(size: 9, weight: .bold, design: .default)
}
