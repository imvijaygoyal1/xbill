//
//  XBillTheme.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

// MARK: - Central Design Theme
// Design inspired by Clay: warm cream canvas, oat borders, named swatch palette,
// generous radius, multi-layer clay shadow, playful press animations.

enum XBillTheme {

    // MARK: - Colors
    static let background   = Color.bgSecondary      // warm cream #faf9f7
    static let surface      = Color.bgCard            // white card surface
    static let primaryBrand = Color.brandPrimary      // Ube 800 #43089f
    static let accentMint   = Color.brandAccent       // Matcha 600 #078a52
    static let accentCoral  = Color.clayPomegranate   // Pomegranate 400 #fc7981

    // MARK: - Clay shadow (multi-layer: cast + inset highlight + edge)
    static let shadowColor:  Color   = .black.opacity(0.10)
    static let shadowRadius: CGFloat = 1
    static let shadowX:      CGFloat = 0
    static let shadowY:      CGFloat = 1

    // MARK: - Card corner radius (clay: 24pt feature card)
    static let cardRadius:   CGFloat = 24
    static let sectionRadius: CGFloat = 40
}

// MARK: - ClayCard ViewModifier
// White surface, 24pt corners, warm oat border, multi-layer clay shadow.

struct ClayCard: ViewModifier {
    var dashed: Bool = false

    func body(content: Content) -> some View {
        content
            .background(XBillTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: XBillTheme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: XBillTheme.cardRadius)
                    .stroke(
                        Color.clayOatBorder,
                        style: dashed
                            ? StrokeStyle(lineWidth: 1, dash: [6, 4])
                            : StrokeStyle(lineWidth: 1)
                    )
            )
            // Layer 1: downward cast
            .shadow(color: .black.opacity(0.10), radius: 1, x: 0, y: 1)
            // Layer 2: edge softener
            .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: -1)
    }
}

extension View {
    func asClayCard(dashed: Bool = false) -> some View {
        modifier(ClayCard(dashed: dashed))
    }

    /// Alias kept for backwards compatibility — routes to clay card style.
    func asSharpCard() -> some View {
        modifier(ClayCard())
    }
}

// MARK: - ClayButtonStyle
// Press: scale down slightly + 3° rotation + hard offset shadow appears.

struct ClayButtonStyle: ButtonStyle {
    var swatchColor: Color = Color.clayUbe

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .rotationEffect(.degrees(configuration.isPressed ? -3 : 0))
            .shadow(
                color: configuration.isPressed ? .black.opacity(0.8) : .clear,
                radius: 0,
                x: configuration.isPressed ? -4 : 0,
                y: configuration.isPressed ? 4 : 0
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Swatch Section Modifier
// Full-width colored background sections (Matcha, Ube, Slushie, Lemon).

struct SwatchSection: ViewModifier {
    let color: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

extension View {
    func swatchSection(_ color: Color, radius: CGFloat = XBillTheme.sectionRadius) -> some View {
        modifier(SwatchSection(color: color, radius: radius))
    }
}
