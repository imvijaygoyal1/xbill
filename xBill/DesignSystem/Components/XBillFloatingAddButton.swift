//
//  XBillFloatingAddButton.swift
//  xBill
//

import SwiftUI

struct XBillFloatingAddButton: View {
    @Environment(\.colorScheme) private var colorScheme
    var systemImage = "plus"
    let action: () -> Void

    /// The brand colour moves to the **glyph** on iOS 26 and stays on the **fill** below it.
    ///
    /// A full-strength `.tint()` renders glass as a near-solid disc, which cancels out the effect
    /// White, because the fill stays tinted.
    ///
    /// Clear glass with a purple glyph was tried and **rejected on device**: it showed genuine
    /// translucence, but it stopped reading as an elevated, floating control — it looked embedded
    /// in the list rather than above it. For the app's primary action, prominence beats the
    /// effect. The translucence was the better demo and the worse button.
    ///
    /// `AmountBadge` keeps its tint for a different reason — there, colour is *information*
    /// (green "owed to you" vs red "you owe"), so untinted glass would erase meaning rather than
    /// just prominence.
    private var glyphColor: Color { AppColors.textInverse }

    var body: some View {
        let shadow = AppShadow.fab(colorScheme: colorScheme)
        Button {
            HapticManager.impact(.medium)
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.appH2)
                .foregroundStyle(glyphColor)
                .frame(width: 56, height: 56)
                .liquidGlassButton(tint: AppColors.primary, fallback: AppColors.primary, in: Circle())
                // Without this the hit area is the glyph's **rendered strokes**, not the 56pt
                // circle: `.background` paints but adds no hit region and `.clipShape` only clips,
                // so taps landing in the gaps of the `+` did nothing and the button appeared to
                // need several presses. Device-reported.
                .contentShape(Circle())
                .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add")
    }
}
