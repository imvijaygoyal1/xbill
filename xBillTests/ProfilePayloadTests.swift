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

    /// C-1 regression test: `User.init(from:)` decodes `paypalHandle` as
    /// `(try? decode(.paypalHandle)) ?? (try? decode(.paypalEmail))`. `try?` flattening
    /// (SE-0230) collapses an explicit JSON `null` for `paypal_handle` to a plain `nil`,
    /// so an account whose legacy `paypal_email` column still holds a value (every
    /// pre-036 account, since migration 036 copied the handle into the new column and
    /// left the old one populated) would have a cleared handle resurrected straight from
    /// `paypal_email` on the very next decode.
    ///
    /// This reproduces the real request shape: `AuthService.updateProfile` sends a PATCH
    /// built from `UserUpdatePayload`, and Postgres/PostgREST applies it key-by-key over
    /// the existing row before `.select().single()` reads it back — exactly what merging
    /// the encoded payload over a stale base row simulates below. Without the fix (mirroring
    /// `paypal_handle` onto `paypal_email` in lockstep), the payload would carry no
    /// `paypal_email` key at all, the merge would leave the row's old `"legacyhandle"`
    /// value untouched, and this test would fail with `paypalHandle == "legacyhandle"`.
    @Test("Clearing a PayPal handle does not resurrect a stale paypal_email on a pre-036 row")
    func clearedPaypalHandleSurvivesServerRoundTrip() throws {
        // A pre-036 profile row: paypal_email still holds the value migration 036 copied
        // into paypal_handle, and both columns currently agree.
        var row: [String: Any] = [
            "id": UUID().uuidString,
            "email": "vijay@example.com",
            "display_name": "Vijay",
            "avatar_url": NSNull(),
            "venmo_handle": NSNull(),
            "paypal_handle": "vijaypay",
            "paypal_email": "vijaypay",
            "is_active": true,
            "created_at": ISO8601DateFormatter().string(from: Date())
        ]

        // The user clears their PayPal handle and saves.
        let payload = UserUpdatePayload(
            displayName: "Vijay",
            avatarURL: nil,
            venmoHandle: nil,
            paypalHandle: nil
        )
        let payloadJSON = try encoded(payload)

        // Apply the PATCH onto the row exactly as PostgREST would: every key present in
        // the payload overwrites the row's existing value, explicit null included.
        for (key, value) in payloadJSON {
            row[key] = value
        }

        // Re-decode as if this were the body of the `.update(payload).select().single()`
        // response.
        let data = try JSONSerialization.data(withJSONObject: row)
        let user = try JSONDecoder().decode(User.self, from: data)

        #expect(user.paypalHandle == nil)
    }
}
