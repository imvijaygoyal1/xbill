//
//  ProfilePayloadTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  Swift's synthesized Encodable uses encodeIfPresent for optionals, which omits a nil
//  key entirely. A PATCH that omits `venmo_handle` leaves the existing column untouched,
//  so "delete the handle and Save" silently did nothing — the handle stayed on the
//  profile and kept rendering a payment button on every settle-up screen.
//
//  ProfileViewModel.saveProfile treats an empty field as a deliberate clear. That intent
//  only reaches the database if nil is encoded as an explicit JSON null, so these tests
//  pin the wire format rather than the Swift value.
//

import Foundation
import Testing
@testable import xBill

@Suite("Profile update payload encoding")
struct ProfilePayloadTests {

    private func encoded(_ payload: UserUpdatePayload) throws -> [String: Any] {
        let data = try JSONEncoder().encode(payload)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("A nil payment handle encodes as an explicit null, not an omitted key")
    func nilHandlesEncodeAsNull() throws {
        let json = try encoded(UserUpdatePayload(
            displayName: "Vijay",
            avatarURL: nil,
            venmoHandle: nil,
            paypalHandle: nil
        ))

        // The keys must be present — an omitted key is a no-op PATCH that cannot clear.
        #expect(json.keys.contains("venmo_handle"))
        #expect(json.keys.contains("paypal_handle"))
        #expect(json["venmo_handle"] is NSNull)
        #expect(json["paypal_handle"] is NSNull)
    }

    @Test("Non-nil payment handles encode as their string value")
    func handlesEncodeAsStrings() throws {
        let json = try encoded(UserUpdatePayload(
            displayName: "Vijay",
            avatarURL: nil,
            venmoHandle: "vijaygoyal",
            paypalHandle: "imvijaygoyal"
        ))
        #expect(json["venmo_handle"] as? String == "vijaygoyal")
        #expect(json["paypal_handle"] as? String == "imvijaygoyal")
    }

    /// avatarURL deliberately keeps omit-on-nil semantics: callers pass the *current*
    /// avatar when no new image was picked, so encoding an explicit null there would
    /// erase an existing avatar on every profile save.
    @Test("A nil avatar URL is omitted rather than nulled")
    func nilAvatarIsOmitted() throws {
        let json = try encoded(UserUpdatePayload(
            displayName: "Vijay",
            avatarURL: nil,
            venmoHandle: "vijaygoyal",
            paypalHandle: nil
        ))
        #expect(!json.keys.contains("avatar_url"))
    }

    @Test("One handle can be cleared while the other is kept")
    func mixedClearAndKeep() throws {
        let json = try encoded(UserUpdatePayload(
            displayName: "Vijay",
            avatarURL: nil,
            venmoHandle: nil,
            paypalHandle: "imvijaygoyal"
        ))
        #expect(json["venmo_handle"] is NSNull)
        #expect(json["paypal_handle"] as? String == "imvijaygoyal")
    }
}
