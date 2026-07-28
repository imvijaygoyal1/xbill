//
//  PaymentLinkService.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation

// MARK: - PaymentLinkService

final class PaymentLinkService: Sendable {
    static let shared = PaymentLinkService()
    private init() {}

    // MARK: - Generate Links

    func paymentLink(
        for suggestion: SettlementSuggestion,
        recipient: User,
        method: Settlement.PaymentMethod
    ) -> URL? {
        switch method {
        case .venmo:
            guard let username = PaymentHandleValidator.normalized(recipient.venmoHandle, for: .venmo) else { return nil }
            return venmoLink(to: username, amount: suggestion.amount, note: "xBill settlement")
        case .paypal:
            guard let username = PaymentHandleValidator.normalized(recipient.paypalHandle, for: .paypal) else { return nil }
            return paypalLink(to: username, amount: suggestion.amount, currency: suggestion.currency)
        case .upi:     return nil   // UPI links are user-specific; handled separately
        default:       return nil
        }
    }

    /// The provider's public profile page, with no amount. Used by "test your link"
    /// so the handle's owner can confirm it resolves without opening a payment screen.
    ///
    /// Verified 2026-07-26: `venmo.com/u/<handle>` returns 404 for a nonexistent handle,
    /// while `paypal.me/<handle>` returns 200 and renders PayPal's own error page.
    func profileLink(handle: String?, method: Settlement.PaymentMethod) -> URL? {
        switch method {
        case .venmo:
            guard let username = PaymentHandleValidator.normalized(handle, for: .venmo) else { return nil }
            return URL(string: "https://venmo.com/u/\(username)")
        case .paypal:
            guard let username = PaymentHandleValidator.normalized(handle, for: .paypal) else { return nil }
            return URL(string: "https://paypal.me/\(username)")
        default:
            return nil
        }
    }

    // MARK: - Amount formatting

    /// Renders a money amount for a payment URL as exactly two decimal places.
    ///
    /// String-interpolating a `Decimal` drops trailing zeros, so 1.90 becomes "1.9" and
    /// 95.00 becomes "95". Verified on-device 2026-07-27: PayPal.Me **ignores** a
    /// single-decimal amount — `paypal.me/<handle>/1.9USD` silently renders the plain
    /// profile page, while `paypal.me/<handle>/5.00USD` opens a real payment screen for
    /// $5.00. Every round settlement amount was therefore producing a link that dropped
    /// the amount entirely.
    ///
    /// `en_US_POSIX` keeps the separator a dot regardless of device locale, and grouping
    /// is disabled so 1234.50 renders "1234.50" rather than a URL-breaking "1,234.50".
    nonisolated(unsafe) private static let amountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    static func formattedAmount(_ amount: Decimal) -> String {
        amountFormatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }

    // MARK: - Venmo

    private func venmoLink(to username: String, amount: Decimal, note: String) -> URL? {
        var components = URLComponents()
        components.scheme = "venmo"
        components.host   = "paycharge"
        components.queryItems = [
            URLQueryItem(name: "txn",        value: "pay"),
            URLQueryItem(name: "recipients", value: username),
            URLQueryItem(name: "amount",     value: Self.formattedAmount(amount)),
            URLQueryItem(name: "note",       value: note)
        ]
        return components.url
    }

    // MARK: - PayPal

    /// https://paypal.me/<username>/<amount><currency>
    private func paypalLink(to username: String, amount: Decimal, currency: String) -> URL? {
        URL(string: "https://paypal.me/\(username)/\(Self.formattedAmount(amount))\(currency)")
    }

    // MARK: - UPI (India)

    /// upi://pay?pa=<upiID>&am=<amount>&cu=INR&tn=<note>
    func upiLink(upiID: String, amount: Decimal, note: String) -> URL? {
        var components = URLComponents()
        components.scheme = "upi"
        components.host   = "pay"
        components.queryItems = [
            URLQueryItem(name: "pa", value: upiID),
            URLQueryItem(name: "am", value: "\(amount)"),
            URLQueryItem(name: "cu", value: "INR"),
            URLQueryItem(name: "tn", value: note)
        ]
        return components.url
    }

    // MARK: - Share Text

    func shareText(for suggestion: SettlementSuggestion) -> String {
        let amount = suggestion.amount.formatted(currencyCode: suggestion.currency)
        return "Hey \(suggestion.toName), I owe you \(amount) via xBill. Let's settle up!"
    }
}
