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
    func errorAlert(error: Binding<AppError?>) -> some View {
        alert(
            error.wrappedValue?.errorDescription ?? "Something went wrong",
            isPresented: Binding(
                get: { error.wrappedValue != nil },
                set: { if !$0 { error.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) { error.wrappedValue = nil }
        }
    }

    /// Persistent error alert — stays on screen until user taps OK.
    /// Use this with `ErrorAlert?` from ViewModels to prevent auto-dismissal on state updates.
    func errorAlert(item: Binding<ErrorAlert?>) -> some View {
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
}
