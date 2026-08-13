//
//  Extensions.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import SwiftUI

// MARK: - Decimal

extension Decimal {
    /// Formats as a currency string using the given currency code.
    func formatted(currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: self as NSDecimalNumber) ?? "\(currencyCode) \(self)"
    }

    /// The canonical machine-readable two-decimal rendering: `1234.50`, never `1,234.5`.
    ///
    /// One definition, because a second copy drifts. This project has produced that failure three
    /// times — `PaymentHandleValidator` (three disagreeing handle rules), and `VisionService`'s
    /// `parseQuantity`/`stripQuantityPrefix` and `extractDecimal`/`stripPrice` pairs, where a fix
    /// was applied to one regex of a pair and not the other.
    ///
    /// Formats the `Decimal` **directly**: `String(format: "%.2f", NSDecimalNumber(...).doubleValue)`
    /// routes money through a binary float, which is the pattern that gave scanned receipts
    /// amounts like `4.990000000000001024` (VIS-04). `en_US_POSIX` and no grouping separator so
    /// the output is parseable — a comma would break both a CSV column and a payment URL.
    var plainTwoDecimalString: String {
        Self.plainFormatter.string(from: self as NSDecimalNumber)
            ?? "\(Self.roundedToTwoPlaces(self))"
    }

    private static let plainFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.usesGroupingSeparator = false
        f.roundingMode = .halfEven
        return f
    }()

    /// Decimal-only fallback for the (practically unreachable) formatter failure — still no `Double`.
    private static func roundedToTwoPlaces(_ value: Decimal) -> Decimal {
        var result = Decimal(); var mutable = value
        NSDecimalRound(&result, &mutable, 2, .bankers)
        return result
    }

    /// Rounds to two decimal places using bankers rounding.
    var rounded: Decimal {
        var result = Decimal()
        var mutable = self
        NSDecimalRound(&result, &mutable, 2, .bankers)
        return result
    }

    var isPositive: Bool { self > .zero }
    var isNegative: Bool { self < .zero }
}

// MARK: - Date

extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: .now)
    }

    var shortFormatted: String {
        formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - Array

extension Array where Element: Identifiable {
    func replacing(_ element: Element) -> [Element] {
        map { $0.id == element.id ? element : $0 }
    }

    func removing(id: Element.ID) -> [Element] {
        filter { $0.id != id }
    }
}

// MARK: - Color

extension Color {
    static let xBillPrimary = Color("xBillPrimary", bundle: .main)
    static let xBillAccent = Color("xBillAccent", bundle: .main)

    /// Returns green for positive, red for negative, secondary for zero.
    static func balance(_ amount: Decimal) -> Color {
        if amount > .zero { return .green }
        if amount < .zero { return .red }
        return .secondary
    }

    /// Initializes a Color from a hex string (e.g. "#FF6B6B" or "FF6B6B").
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch hex.count {
        case 6:
            (r, g, b, a) = (int >> 16, int >> 8 & 0xFF, int & 0xFF, 255)
        case 8:
            (r, g, b, a) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (0, 0, 0, 255)
        }
        self.init(
            .sRGB,
            red:     Double(r) / 255,
            green:   Double(g) / 255,
            blue:    Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View

extension View {
    func errorAlert(error: Binding<AppError?>, fileID: String = #fileID, line: Int = #line) -> some View {
        alert(
            error.wrappedValue?.errorDescription ?? "Something went wrong",
            isPresented: Binding(
                get: { error.wrappedValue != nil },
                set: { if !$0 { error.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) { error.wrappedValue = nil }
        }
        // Instrumentation chokepoint: records every alert actually shown to the user,
        // whatever its origin. See DEFECT_HANDOFF_VENMO_BALANCES.md.
        .onChange(of: error.wrappedValue) { _, newValue in
            guard let newValue else { return }
            AppDiagnostics.log(.lifecycle, "alert.presented", [
                ("binding", "error"),
                ("callSite", "\(fileID):\(line)"),
                ("title", newValue.errorDescription ?? "Something went wrong")
            ])
        }
    }

    /// Persistent error alert — stays on screen until user taps OK.
    /// Use this with `ErrorAlert?` from ViewModels to prevent auto-dismissal on state updates.
    func errorAlert(item: Binding<ErrorAlert?>, fileID: String = #fileID, line: Int = #line) -> some View {
        let title   = item.wrappedValue?.title   ?? ""
        let message = item.wrappedValue?.message ?? ""
        return alert(title, isPresented: Binding(
            get: { item.wrappedValue != nil },
            set: { if !$0 { item.wrappedValue = nil } }
        )) {
            Button("OK", role: .cancel) { item.wrappedValue = nil }
        } message: {
            Text(message)
        }
        // Instrumentation chokepoint: records every alert actually shown to the user,
        // whatever its origin. See DEFECT_HANDOFF_VENMO_BALANCES.md.
        .onChange(of: item.wrappedValue?.id) { _, newValue in
            guard newValue != nil else { return }
            AppDiagnostics.log(.lifecycle, "alert.presented", [
                ("binding", "item"),
                ("callSite", "\(fileID):\(line)"),
                ("title", item.wrappedValue?.title ?? ""),
                ("message", item.wrappedValue?.message ?? "")
            ])
        }
    }

    /// Non-interactive Liquid Glass on iOS 26+; regular material on earlier OS.
    @ViewBuilder
    func liquidGlass(in shape: some Shape) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }

    /// Non-interactive Liquid Glass on iOS 26+; custom fallback style on earlier OS.
    @ViewBuilder
    func liquidGlass(fallback: some ShapeStyle, in shape: some Shape) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(fallback, in: shape)
        }
    }

    /// Interactive Liquid Glass on iOS 26+; flat tinted fill on earlier OS.
    @ViewBuilder
    func liquidGlassButton(fallback: some ShapeStyle, in shape: some Shape) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(fallback, in: shape)
        }
    }

    // MARK: - Tinted glass
    //
    // Untinted glass takes its colour from whatever is behind it, which destroys any colour that
    // *carries meaning*. `AmountBadge` is the clear case: green means owed to you and red means
    // you owe, and a plain `.regular` glass would render both identically. `.tint()` keeps the
    // semantic fill and lets glass supply only the depth and refraction.
    //
    // Both fall back to a flat fill below iOS 26 — the deployment target is **17.0**, so an
    // unguarded `glassEffect` would not compile, and every glass surface in the app must have a
    // defined non-glass appearance.

    /// Tinted, non-interactive Liquid Glass on iOS 26+; flat `fallback` fill on earlier OS.
    @ViewBuilder
    func liquidGlass(tint: Color, fallback: some ShapeStyle, in shape: some Shape) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular.tint(tint), in: shape)
        } else {
            self.background(fallback, in: shape)
        }
    }

    /// Tinted, interactive Liquid Glass on iOS 26+; flat `fallback` fill on earlier OS.
    /// Use for controls that must keep a brand or semantic colour — a primary CTA whose fill is
    /// the affordance cannot become clear glass without losing its prominence.
    @ViewBuilder
    func liquidGlassButton(tint: Color, fallback: some ShapeStyle, in shape: some Shape) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            self.background(fallback, in: shape)
        }
    }
}
