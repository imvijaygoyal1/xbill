//
//  PaymentHandleValidator.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  Single source of truth for Venmo / PayPal.Me handle rules.
//
//  Both ProfileView (input) and PaymentLinkService (output) validate through this
//  type. They previously carried three separate, disagreeing rule sets, so a handle
//  could pass entry and still fail to produce a link.
//
//  Rules are taken from the providers' own documentation, not inferred:
//    PayPal.Me — "between 3 and 20 characters", "only using letters and numbers"
//    Venmo     — "between 5 and 30 characters", "no special characters other than - and _"
//                https://help.venmo.com/cs/articles/check-or-edit-your-username-vhel208
//
//  The charsets must stay separate: - and _ are legal for Venmo and illegal for
//  PayPal. A dot is illegal for both.
//

import Foundation

enum PaymentHandleValidator {

    enum Provider: Equatable, Sendable {
        case venmo
        case paypal

        var displayName: String {
            switch self {
            case .venmo:  return "Venmo"
            case .paypal: return "PayPal"
            }
        }

        var minLength: Int {
            switch self {
            case .venmo:  return 5
            case .paypal: return 3
            }
        }

        var maxLength: Int {
            switch self {
            case .venmo:  return 30
            case .paypal: return 20
            }
        }

        /// Venmo permits `-` and `_`; PayPal.Me permits neither.
        var allowsSeparators: Bool { self == .venmo }

        var charsetMessage: String {
            switch self {
            case .venmo:  return "Venmo handles use letters, numbers, dashes and underscores."
            case .paypal: return "PayPal.Me handles use letters and numbers only."
            }
        }

        var lengthMessage: String {
            "\(displayName) handles are \(minLength)–\(maxLength) characters."
        }
    }

    enum Result: Equatable, Sendable {
        case valid(String)
        case invalid(reason: String)
        case empty
    }

    /// ASCII only — provider rules do not permit accented or non-Latin characters,
    /// and `CharacterSet.alphanumerics` would wrongly accept them.
    private static let asciiAlphanumerics = Set(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    )

    static func validate(_ raw: String?, for provider: Provider) -> Result {
        var value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("@") { value.removeFirst() }
        guard !value.isEmpty else { return .empty }

        var allowed = asciiAlphanumerics
        if provider.allowsSeparators {
            allowed.formUnion(["-", "_"])
        }
        guard value.allSatisfy({ allowed.contains($0) }) else {
            return .invalid(reason: provider.charsetMessage)
        }
        guard value.count >= provider.minLength, value.count <= provider.maxLength else {
            return .invalid(reason: provider.lengthMessage)
        }
        return .valid(value)
    }

    /// The normalised handle when valid, otherwise nil. Use when a link is being built.
    static func normalized(_ raw: String?, for provider: Provider) -> String? {
        guard case .valid(let handle) = validate(raw, for: provider) else { return nil }
        return handle
    }
}
