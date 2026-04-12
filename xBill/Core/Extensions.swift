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
