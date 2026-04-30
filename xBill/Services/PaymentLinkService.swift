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
        method: Settlement.PaymentMethod
    ) -> URL? {
        switch method {
        case .venmo:   return venmoLink(to: suggestion.toName, amount: suggestion.amount, note: "xBill settlement")
        case .paypal:  return paypalLink(to: suggestion.toName, amount: suggestion.amount, currency: suggestion.currency)
        case .upi:     return nil   // UPI links are user-specific; handled separately
        default:       return nil
        }
    }

    // MARK: - Venmo

    /// venmo://paycharge?txn=pay&recipients=<username>&amount=<amount>&note=<note>
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
        let path = "https://paypal.me/\(username)/\(amount)\(currency)"
        return URL(string: path)
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
