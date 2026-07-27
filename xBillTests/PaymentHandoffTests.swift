//
//  PaymentHandoffTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  Regression coverage for the Venmo/PayPal settle-up handoff.
//
//  Root cause of the "Something went wrong" defect (2026-07-27): the App Store
//  reviewer seed populated venmo_handle/paypal_handle with the fabricated value
//  'appreviewer'. PaymentLinkService turned that into a live deep link, and the
//  PayPal app resolved https://paypal.me/appreviewer/95USD, found no such
//  profile, and displayed its own "Something went wrong" error. The failure was
//  entirely outside xBill — on-device logs recorded zero xBill alerts — but it
//  read as an xBill defect and three previous fixes were aimed at xBill's own
//  lifecycle code as a result.
//
//  These tests pin the contract that makes the seed fix effective: when a
//  recipient has no usable handle, PaymentLinkService must return nil so
//  GroupDetailView renders no payment button and no broken link can be reached.
//

import Foundation
import Testing
@testable import xBill

@Suite("Payment handoff link generation")
struct PaymentHandoffTests {

    private func recipient(venmo: String? = nil, paypal: String? = nil) -> User {
        User(
            id: UUID(),
            email: "recipient@example.com",
            displayName: "App Reviewer",
            avatarURL: nil,
            venmoHandle: venmo,
            paypalEmail: paypal,
            createdAt: Date()
        )
    }

    private func suggestion(amount: Decimal = 95, currency: String = "USD") -> SettlementSuggestion {
        SettlementSuggestion(
            id: UUID(),
            fromUserID: UUID(),
            fromName: "Alice Chen",
            toUserID: UUID(),
            toName: "App Reviewer",
            amount: amount,
            currency: currency
        )
    }

    // MARK: - No handle ⇒ no link ⇒ no button

    @Test("PayPal link is nil when the recipient has no handle")
    func paypalLinkNilWithoutHandle() {
        let url = PaymentLinkService.shared.paymentLink(
            for: suggestion(),
            recipient: recipient(paypal: nil),
            method: .paypal
        )
        #expect(url == nil)
    }

    @Test("Venmo link is nil when the recipient has no handle")
    func venmoLinkNilWithoutHandle() {
        let url = PaymentLinkService.shared.paymentLink(
            for: suggestion(),
            recipient: recipient(venmo: nil),
            method: .venmo
        )
        #expect(url == nil)
    }

    @Test("Blank and whitespace-only handles never produce a link", arguments: ["", "   ", "\n", "\t "])
    func blankHandlesProduceNoLink(_ handle: String) {
        let service = PaymentLinkService.shared
        let sugg = suggestion()
        #expect(service.paymentLink(for: sugg, recipient: recipient(paypal: handle), method: .paypal) == nil)
        #expect(service.paymentLink(for: sugg, recipient: recipient(venmo: handle), method: .venmo) == nil)
    }

    /// The seeded reviewer profile must not carry payment handles. This mirrors
    /// the post-fix state of seed_app_store_review_account.sql, where every
    /// seeded profile has NULL venmo_handle and NULL paypal_handle.
    @Test("A seeded demo profile with no handles exposes no payment buttons")
    func seededDemoProfileExposesNoPaymentButtons() {
        let seeded = recipient(venmo: nil, paypal: nil)
        let sugg = suggestion()
        #expect(PaymentLinkService.shared.paymentLink(for: sugg, recipient: seeded, method: .venmo) == nil)
        #expect(PaymentLinkService.shared.paymentLink(for: sugg, recipient: seeded, method: .paypal) == nil)
    }

    // MARK: - URL format

    @Test("PayPal link uses the PayPal.Me amount+currency path format")
    func paypalLinkFormat() throws {
        let url = try #require(PaymentLinkService.shared.paymentLink(
            for: suggestion(amount: 95, currency: "USD"),
            recipient: recipient(paypal: "realhandle"),
            method: .paypal
        ))
        #expect(url.absoluteString == "https://paypal.me/realhandle/95USD")
        #expect(url.scheme == "https")
        #expect(url.host() == "paypal.me")
    }

    /// Decimal's string interpolation drops trailing zeros, so 12.50 becomes
    /// "12.5". PayPal.Me accepts that form. The important guarantee is that the
    /// amount never renders in scientific notation, which would produce a link
    /// PayPal cannot parse.
    @Test("PayPal link renders decimal amounts as a plain decimal", arguments: [
        (Decimal(string: "12.50")!, "12.5"),
        (Decimal(string: "0.05")!, "0.05"),
        (Decimal(string: "1234.5")!, "1234.5"),
        (Decimal(95), "95")
    ])
    func paypalLinkDecimalAmount(_ amount: Decimal, _ expected: String) throws {
        let url = try #require(PaymentLinkService.shared.paymentLink(
            for: suggestion(amount: amount, currency: "EUR"),
            recipient: recipient(paypal: "realhandle"),
            method: .paypal
        ))
        #expect(url.absoluteString == "https://paypal.me/realhandle/\(expected)EUR")
        #expect(!url.absoluteString.lowercased().contains("e+"))
    }

    @Test("A leading @ is stripped from handles before building the link")
    func atPrefixStripped() throws {
        let url = try #require(PaymentLinkService.shared.paymentLink(
            for: suggestion(),
            recipient: recipient(paypal: "@realhandle"),
            method: .paypal
        ))
        #expect(url.absoluteString == "https://paypal.me/realhandle/95USD")
    }

    @Test("Venmo link uses the venmo:// charge scheme with the recipient handle")
    func venmoLinkFormat() throws {
        let url = try #require(PaymentLinkService.shared.paymentLink(
            for: suggestion(),
            recipient: recipient(venmo: "realhandle"),
            method: .venmo
        ))
        #expect(url.scheme == "venmo")
        #expect(url.host == "paycharge")
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.contains(URLQueryItem(name: "recipients", value: "realhandle")))
        #expect(query.contains(URLQueryItem(name: "amount", value: "95")))
        #expect(query.contains(URLQueryItem(name: "txn", value: "pay")))
    }

    @Test("Handles containing URL-unsafe characters are rejected", arguments: [
        "bad handle", "bad/handle", "bad@handle", "bad%handle", "bad?handle", "bad#handle"
    ])
    func unsafeHandlesRejected(_ handle: String) {
        let service = PaymentLinkService.shared
        let sugg = suggestion()
        #expect(service.paymentLink(for: sugg, recipient: recipient(paypal: handle), method: .paypal) == nil)
        #expect(service.paymentLink(for: sugg, recipient: recipient(venmo: handle), method: .venmo) == nil)
    }

    // MARK: - Validator agreement

    @Test("PaymentLinkService accepts exactly what the validator accepts", arguments: [
        "ab",            // too short for both
        "abcd",          // valid PayPal, too short for Venmo
        "my_handle",     // valid Venmo, invalid PayPal
        "my.handle",     // invalid for both
        "realhandle"     // valid for both
    ])
    func serviceAgreesWithValidator(_ handle: String) {
        let sugg = suggestion()
        let paypalURL = PaymentLinkService.shared.paymentLink(
            for: sugg, recipient: recipient(paypal: handle), method: .paypal
        )
        let venmoURL = PaymentLinkService.shared.paymentLink(
            for: sugg, recipient: recipient(venmo: handle), method: .venmo
        )
        #expect((paypalURL != nil) == (PaymentHandleValidator.normalized(handle, for: .paypal) != nil))
        #expect((venmoURL != nil) == (PaymentHandleValidator.normalized(handle, for: .venmo) != nil))
    }

    // MARK: - Profile (test-your-link) URLs

    @Test("PayPal profile link omits the amount")
    func paypalProfileLink() throws {
        let url = try #require(PaymentLinkService.shared.profileLink(handle: "realhandle", method: .paypal))
        #expect(url.absoluteString == "https://paypal.me/realhandle")
    }

    @Test("Venmo profile link uses the verified /u/ path")
    func venmoProfileLink() throws {
        let url = try #require(PaymentLinkService.shared.profileLink(handle: "realhandle", method: .venmo))
        #expect(url.absoluteString == "https://venmo.com/u/realhandle")
    }

    @Test("Profile links reject handles the validator rejects", arguments: ["ab", "my handle", ""])
    func profileLinkRejectsInvalid(_ handle: String) {
        #expect(PaymentLinkService.shared.profileLink(handle: handle, method: .paypal) == nil)
    }
}
