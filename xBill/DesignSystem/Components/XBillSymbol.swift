//
//  XBillSymbol.swift
//  xBill
//
//  The one place that decides how an SF Symbol renders in xBill.
//
//  Before this file the app used **none** of SF Symbols' rendering system: across 47
//  `Image(systemName:)` call sites there were zero uses of `symbolRenderingMode`, zero of
//  `symbolVariant` and zero of `imageScale`, so every glyph — including multi-layer ones like
//  `bell.badge.fill` and `person.badge.plus.fill` — drew flat. `NATIVE_PATTERNS.md` §3 has
//  required hierarchical or palette rendering since it was written; nothing enforced it.
//
//  It is a modifier rather than a convention because a styling rule applied by hand at 47 call
//  sites is a rule that drifts. Three separate defects in this project (SPLIT-05, INV-05,
//  ICON-01) were two copies of one rule disagreeing, and ICON-01 in particular was a *fix* that
//  landed on the copy nobody rendered.
//

import SwiftUI

extension View {

    /// xBill's standard symbol rendering: hierarchical, so a multi-layer glyph keeps the depth
    /// its secondary layers exist to provide, and monochrome glyphs are unaffected.
    ///
    /// Apply to the `Image(systemName:)` itself, before `.foregroundStyle`. Hierarchical
    /// rendering derives its secondary layers from the foreground colour, so the order matters.
    ///
    /// - Note: hierarchical rendering is a **no-op on a single-layer symbol**. Check a glyph in
    ///   the SF Symbols app before assuming this changed anything about it.
    func xbillSymbol() -> some View {
        symbolRenderingMode(.hierarchical)
    }

    /// Two-tone rendering for a symbol whose colour carries meaning rather than decoration —
    /// a settled checkmark, a balance direction.
    ///
    /// Use this rather than `xbillSymbol()` wherever an untinted or hierarchical treatment would
    /// flatten a semantic distinction. Same reasoning as `AmountBadge` keeping its tint under
    /// Liquid Glass: there, colour *is* the information.
    func xbillSymbol(palette primary: Color, _ secondary: Color) -> some View {
        symbolRenderingMode(.palette)
            .foregroundStyle(primary, secondary)
    }
}
