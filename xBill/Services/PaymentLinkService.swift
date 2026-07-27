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

    // MARK: - Venmo

    private func venmoLink(to username: String, amount: Decimal, note: String) -> URL? {
        var components = URLComponents()
        components.scheme = "venmo"
        components.host   = "paycharge"
        components.queryItems = [
            URLQueryItem(name: "txn",        value: "pay"),
            URLQueryItem(name: "recipients", value: username),
            URLQueryItem(name: "amount",     value: "\(amount)"),
            URLQueryItem(name: "note",       value: note)
        ]
        return components.url
    }

    // MARK: - PayPal

    /// https://paypal.me/<username>/<amount><currency>
    private func paypalLink(to username: String, amount: Decimal, currency: String) -> URL? {
        URL(string: "https://paypal.me/\(username)/\(amount)\(currency)")
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
