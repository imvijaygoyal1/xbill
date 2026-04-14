import SwiftUI

// MARK: - Central Design Theme

/// Single source of truth for the "Professional Sharp" visual identity.
enum XBillTheme {

    // MARK: - Colors (bridge to named asset tokens)
    static let background   = Color.bgSecondary       // #F8F9FB light, adaptive dark
    static let surface      = Color.bgCard            // white / near-white card surface
    static let primaryBrand = Color.brandPrimary      // #2F2356 deep navy-violet
    static let accentMint   = Color.brandAccent       // #00A86B mint green
    static let accentCoral  = Color(hex: "#FF6B6B")   // coral red (new)

    // MARK: - Sharp card shadow
    static let shadowColor:  Color   = .black.opacity(0.04)
    static let shadowRadius: CGFloat = 12
    static let shadowX:      CGFloat = 0
    static let shadowY:      CGFloat = 6

    // MARK: - Card corner radius
    static let cardRadius:   CGFloat = 18
}

// MARK: - SharpCard ViewModifier

/// Applies the "Professional Sharp" card treatment:
/// white surface, 18pt corners, hairline border, and a barely-there drop shadow.
struct SharpCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(XBillTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: XBillTheme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: XBillTheme.cardRadius)
                    .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(
                color:  XBillTheme.shadowColor,
                radius: XBillTheme.shadowRadius,
                x:      XBillTheme.shadowX,
                y:      XBillTheme.shadowY
            )
    }
}

extension View {
    func asSharpCard() -> some View {
        modifier(SharpCard())
    }
}
