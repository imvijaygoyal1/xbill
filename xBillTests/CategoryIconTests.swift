//
//  CategoryIconTests.swift
//  xBillTests
//
//  ICON-01 / ICON-02. Two properties are asserted here that no previous test covered:
//  that `Expense.Category` has exactly **one** symbol vocabulary, and that the glyph colour is
//  legible on its own swatch in **both** appearances.
//
//  Both are written to fail against the pre-fix code. The contrast suite in particular is the
//  point: the defect it guards was invisible to every screenshot review because light mode was
//  always fine — only the dark variants of the `Cat*` colorsets moved.
//

import Testing
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
@testable import xBill

// MARK: - ICON-01 — one vocabulary

@Suite("Category symbol vocabulary")
struct CategorySymbolVocabularyTests {

    /// The collision `Expense.swift:79` forbids in a comment, asserted so the comment cannot be
    /// the only thing enforcing it. `symbolName` mapped `.accommodation` to `house.fill` for
    /// two weeks after `systemImage` was corrected, on four screens.
    @Test("No category reuses a tab-bar glyph")
    func noTabBarCollision() {
        // MainTabView.swift — Home / Groups / Friends / Recent / Profile.
        let tabSymbols: Set<String> = [
            "house.fill", "person.3.fill", "person.2.fill", "bell.fill", "person.crop.circle.fill"
        ]
        for category in Expense.Category.allCases {
            #expect(
                !tabSymbols.contains(category.systemImage),
                "\(category.rawValue) uses \(category.systemImage), which is a tab-bar glyph"
            )
        }
    }

    /// `sparkles` is the Apple Intelligence glyph from iOS 18 onward. It read as "AI", not "other".
    @Test("No category uses a system-reserved glyph")
    func noReservedGlyphs() {
        let reserved: Set<String> = ["sparkles", "apple.intelligence"]
        for category in Expense.Category.allCases {
            #expect(!reserved.contains(category.systemImage), "\(category.rawValue) uses a reserved glyph")
        }
    }

    /// Eight categories must be eight distinguishable icons — a duplicate makes two categories
    /// indistinguishable in the filter chip row, where the icon is most of the affordance.
    @Test("Every category has a distinct symbol")
    func symbolsAreUnique() {
        let symbols = Expense.Category.allCases.map(\.systemImage)
        #expect(Set(symbols).count == symbols.count, "duplicate symbol in \(symbols)")
    }

    @Test("Every category has a non-empty symbol")
    func symbolsAreNonEmpty() {
        for category in Expense.Category.allCases {
            #expect(!category.systemImage.isEmpty)
        }
    }
}

// MARK: - ICON-02 — contrast on the swatch

@Suite("Category icon contrast")
struct CategoryIconContrastTests {

    /// WCAG 2.1 non-text contrast minimum. An icon is a graphical object, not text.
    private static let minimumRatio = 3.0

    /// sRGB relative luminance, WCAG 2.1 formula.
    private static func luminance(_ rgb: (Double, Double, Double)) -> Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.0) + 0.7152 * channel(rgb.1) + 0.0722 * channel(rgb.2)
    }

    private static func ratio(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Resolves a SwiftUI `Color` in a named appearance. This is what makes the test able to see
    /// the defect at all: the failing values only exist in the dark trait collection, and a test
    /// that resolves in the default appearance reports light-mode numbers and passes.
    private static func components(
        _ color: Color,
        _ style: UIUserInterfaceStyle
    ) -> (Double, Double, Double) {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }

    @Test("Glyph clears 3:1 on its swatch in both appearances", arguments: Expense.Category.allCases)
    func glyphIsLegibleOnItsSwatch(category: Expense.Category) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let glyph = Self.components(AppColors.categoryGlyph, style)
            let swatch = Self.components(category.categoryBackground, style)
            let r = Self.ratio(glyph, swatch)
            #expect(
                r >= Self.minimumRatio,
                """
                \(category.rawValue) in \(style == .dark ? "dark" : "light"): \
                \(String(format: "%.2f", r)):1 — below the 3:1 non-text minimum
                """
            )
        }
    }

    /// A guard that cannot fail is not a guard. This pins the measurement itself: the pre-fix
    /// colour must still be *rejected* by the same code path, so a future change that quietly
    /// widens `minimumRatio` or breaks `components(_:_:)` fails here rather than passing silently.
    @Test("The measurement still rejects the colour that caused ICON-02")
    func measurementRejectsThePreFixColour() {
        let preFixGlyph = Self.components(AppColors.primary, .dark)   // #6C35FF, both appearances
        let swatch = Self.components(Expense.Category.accommodation.categoryBackground, .dark)
        let r = Self.ratio(preFixGlyph, swatch)
        #expect(r < Self.minimumRatio, "expected the pre-fix pairing to fail, measured \(r):1")
    }

    /// Light mode was never the problem and must not be traded away to fix dark mode.
    @Test("Light mode is unchanged by the dark-mode fix")
    func lightModeStillUsesPrimary() {
        let glyph = Self.components(AppColors.categoryGlyph, .light)
        let primary = Self.components(AppColors.primary, .light)
        #expect(abs(glyph.0 - primary.0) < 0.01)
        #expect(abs(glyph.1 - primary.1) < 0.01)
        #expect(abs(glyph.2 - primary.2) < 0.01)
    }
}
