//
//  PaymentHandleValidatorTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import Testing
@testable import xBill

@Suite("Payment handle validation")
struct PaymentHandleValidatorTests {

    typealias Validator = PaymentHandleValidator

    // MARK: - Empty

    @Test("Nil, empty and whitespace-only input is empty, not invalid", arguments: [nil, "", "   ", "\n", "@"])
    func emptyInput(_ raw: String?) {
        #expect(Validator.validate(raw, for: .paypal) == .empty)
        #expect(Validator.validate(raw, for: .venmo) == .empty)
    }

    // MARK: - PayPal length bounds (3–20)

    @Test("PayPal rejects handles shorter than 3", arguments: ["a", "ab"])
    func paypalTooShort(_ handle: String) {
        guard case .invalid = Validator.validate(handle, for: .paypal) else {
            Issue.record("Expected \(handle) to be invalid for PayPal")
            return
        }
    }

    @Test("PayPal accepts 3 and 20 character handles")
    func paypalLengthBounds() {
        #expect(Validator.validate("abc", for: .paypal) == .valid("abc"))
        let twenty = String(repeating: "a", count: 20)
        #expect(Validator.validate(twenty, for: .paypal) == .valid(twenty))
    }

    @Test("PayPal rejects handles longer than 20")
    func paypalTooLong() {
        let twentyOne = String(repeating: "a", count: 21)
        guard case .invalid = Validator.validate(twentyOne, for: .paypal) else {
            Issue.record("Expected a 21-character handle to be invalid for PayPal")
            return
        }
    }

    // MARK: - Venmo length bounds (5–30)

    @Test("Venmo rejects handles shorter than 5", arguments: ["a", "ab", "abc", "abcd"])
    func venmoTooShort(_ handle: String) {
        guard case .invalid = Validator.validate(handle, for: .venmo) else {
            Issue.record("Expected \(handle) to be invalid for Venmo")
            return
        }
    }

    @Test("Venmo accepts 5 and 30 character handles")
    func venmoLengthBounds() {
        #expect(Validator.validate("abcde", for: .venmo) == .valid("abcde"))
        let thirty = String(repeating: "a", count: 30)
        #expect(Validator.validate(thirty, for: .venmo) == .valid(thirty))
    }

    @Test("Venmo rejects handles longer than 30")
    func venmoTooLong() {
        let thirtyOne = String(repeating: "a", count: 31)
        guard case .invalid = Validator.validate(thirtyOne, for: .venmo) else {
            Issue.record("Expected a 31-character handle to be invalid for Venmo")
            return
        }
    }

    // MARK: - Charsets differ per provider

    @Test("PayPal rejects separators and punctuation", arguments: ["ab.cd", "ab-cd", "ab_cd", "ab cd", "ab/cd", "ab@cd", "ab#cd"])
    func paypalRejectsNonAlphanumeric(_ handle: String) {
        guard case .invalid = Validator.validate(handle, for: .paypal) else {
            Issue.record("Expected \(handle) to be invalid for PayPal")
            return
        }
    }

    @Test("Venmo accepts hyphen and underscore")
    func venmoAcceptsSeparators() {
        #expect(Validator.validate("my-handle", for: .venmo) == .valid("my-handle"))
        #expect(Validator.validate("my_handle", for: .venmo) == .valid("my_handle"))
    }

    @Test("Venmo rejects dot, space and slash", arguments: ["my.handle", "my handle", "my/handle"])
    func venmoRejectsOthers(_ handle: String) {
        guard case .invalid = Validator.validate(handle, for: .venmo) else {
            Issue.record("Expected \(handle) to be invalid for Venmo")
            return
        }
    }

    @Test("Non-ASCII characters are rejected by both providers", arguments: ["handlé", "handle✓", "ハンドル"])
    func nonASCIIRejected(_ handle: String) {
        guard case .invalid = Validator.validate(handle, for: .paypal) else {
            Issue.record("Expected \(handle) to be invalid for PayPal")
            return
        }
        guard case .invalid = Validator.validate(handle, for: .venmo) else {
            Issue.record("Expected \(handle) to be invalid for Venmo")
            return
        }
    }

    /// The providers genuinely disagree; a shared charset would be wrong for one of them.
    @Test("A handle can be valid for one provider and invalid for the other")
    func providersDisagree() {
        #expect(Validator.validate("my_handle", for: .venmo) == .valid("my_handle"))
        guard case .invalid = Validator.validate("my_handle", for: .paypal) else {
            Issue.record("Expected my_handle to be invalid for PayPal")
            return
        }
        // "abc" is long enough for PayPal (3) but too short for Venmo (5).
        #expect(Validator.validate("abc", for: .paypal) == .valid("abc"))
        guard case .invalid = Validator.validate("abc", for: .venmo) else {
            Issue.record("Expected abc to be too short for Venmo")
            return
        }
    }

    // MARK: - Normalisation

    @Test("A leading @ is stripped and whitespace trimmed")
    func normalisation() {
        #expect(Validator.validate("  @realhandle  ", for: .paypal) == .valid("realhandle"))
        #expect(Validator.validate("@realhandle", for: .venmo) == .valid("realhandle"))
    }

    @Test("normalized returns the handle only when valid")
    func normalizedHelper() {
        #expect(Validator.normalized("@realhandle", for: .paypal) == "realhandle")
        #expect(Validator.normalized("ab", for: .paypal) == nil)
        #expect(Validator.normalized(nil, for: .venmo) == nil)
    }
}
