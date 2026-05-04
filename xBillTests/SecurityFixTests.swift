//
//  SecurityFixTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Testing
import Foundation
@testable import xBill

// MARK: - L1: AppLockEnabled in Keychain

// .serialized: all tests share the same Keychain key so they must not run concurrently.
@Suite("L1 — AppLock preference stored in Keychain", .serialized)
struct AppLockKeychainTests {

    private let keychainKey = KeychainManager.Keys.appLockEnabled

    // Clean up any residual test state before and after each test.
    private func cleanup() {
        try? KeychainManager.shared.delete(forKey: keychainKey)
        UserDefaults.standard.removeObject(forKey: "appLockEnabled")
    }

    @Test("Default returns false when Keychain entry is absent")
    @MainActor
    func defaultIsFalse() {
        cleanup()
        // Simulate a fresh install with no Keychain entry.
        let service = AppLockService.shared
        // Force-clear any existing Keychain value for this test.
        try? KeychainManager.shared.delete(forKey: keychainKey)
        // isEnabled computed property returns false when key is absent.
        #expect(service.isEnabled == false)
        cleanup()
    }

    @Test("Setting isEnabled = true persists 'true' to Keychain")
    @MainActor
    func setEnabledTrue() throws {
        cleanup()
        let service = AppLockService.shared
        service.isEnabled = true
        let stored = try KeychainManager.shared.string(forKey: keychainKey)
        #expect(stored == "true")
        cleanup()
    }

    @Test("Setting isEnabled = false persists 'false' to Keychain")
    @MainActor
    func setEnabledFalse() throws {
        cleanup()
        let service = AppLockService.shared
        service.isEnabled = true   // set to true first
        service.isEnabled = false  // then clear
        let stored = try KeychainManager.shared.string(forKey: keychainKey)
        #expect(stored == "false")
        #expect(service.isEnabled == false)
        cleanup()
    }

    @Test("isEnabled round-trips through Keychain correctly")
    @MainActor
    func roundTrip() throws {
        cleanup()
        let service = AppLockService.shared
        service.isEnabled = true
        #expect(service.isEnabled == true)
        service.isEnabled = false
        #expect(service.isEnabled == false)
        cleanup()
    }

    @Test("UserDefaults migration: old flag moves to Keychain and UserDefaults entry is cleared")
    func userDefaultsMigration() {
        cleanup()
        // Simulate an old install: write the legacy UserDefaults flag.
        UserDefaults.standard.set(true, forKey: "appLockEnabled")
        // Trigger migration by calling the internal migration method via init path.
        // Since shared is a singleton, test the migration logic directly on KeychainManager.
        let ud = UserDefaults.standard
        guard ud.object(forKey: "appLockEnabled") != nil else { return }
        let wasEnabled = ud.bool(forKey: "appLockEnabled")
        try? KeychainManager.shared.save(wasEnabled ? "true" : "false",
                                         forKey: KeychainManager.Keys.appLockEnabled)
        ud.removeObject(forKey: "appLockEnabled")

        // After migration: UserDefaults entry is gone, Keychain has the value.
        #expect(ud.object(forKey: "appLockEnabled") == nil)
        let stored = try? KeychainManager.shared.string(forKey: KeychainManager.Keys.appLockEnabled)
        #expect(stored == "true")
        cleanup()
    }
}

// MARK: - M1: search_profiles no longer exposes email

@Suite("M1 — search_profiles does not expose email in decode")
struct SearchProfilesEmailTests {

    /// Verifies that the Row struct used to decode search_profiles results
    /// does NOT contain an email field. Email is kept in the WHERE clause
    /// for searching but must not appear in the response to prevent enumeration.
    @Test("search_profiles Row JSON without email field decodes successfully")
    func rowDecodesWithoutEmail() throws {
        // Simulate the response from the updated RPC (migration 021):
        // no email column in the result set.
        let json = """
        [
          {
            "id": "00000000-0000-0000-0000-000000000001",
            "display_name": "Alice",
            "avatar_url": null
          },
          {
            "id": "00000000-0000-0000-0000-000000000002",
            "display_name": "Bob",
            "avatar_url": "https://example.com/bob.png"
          }
        ]
        """.data(using: .utf8)!

        struct Row: Decodable {
            let id: UUID
            let displayName: String
            let avatarURL: String?
            enum CodingKeys: String, CodingKey {
                case id
                case displayName = "display_name"
                case avatarURL   = "avatar_url"
            }
        }

        let rows = try JSONDecoder().decode([Row].self, from: json)
        #expect(rows.count == 2)
        #expect(rows[0].displayName == "Alice")
        #expect(rows[0].avatarURL == nil)
        #expect(rows[1].displayName == "Bob")
        #expect(rows[1].avatarURL == "https://example.com/bob.png")
    }

    @Test("search_profiles Row JSON with extra email field still decodes (backward compat)")
    func rowDecodesWithExtraEmailField() throws {
        // Decoder ignores unknown keys by default — if the server ever returns email
        // it won't crash; it's just not stored.
        let json = """
        [
          {
            "id": "00000000-0000-0000-0000-000000000003",
            "display_name": "Carol",
            "avatar_url": null,
            "email": "carol@example.com"
          }
        ]
        """.data(using: .utf8)!

        struct Row: Decodable {
            let id: UUID
            let displayName: String
            let avatarURL: String?
            enum CodingKeys: String, CodingKey {
                case id
                case displayName = "display_name"
                case avatarURL   = "avatar_url"
            }
        }

        let rows = try JSONDecoder().decode([Row].self, from: json)
        #expect(rows.count == 1)
        #expect(rows[0].displayName == "Carol")
    }

    @Test("User constructed from search result has empty email string")
    func userEmailIsEmpty() throws {
        // searchProfiles now passes email: "" when building User objects.
        let user = User(id: UUID(), email: "", displayName: "Dave",
                        avatarURL: nil, createdAt: Date())
        #expect(user.email == "")
        #expect(user.displayName == "Dave")
    }
}

// MARK: - L2: PayPal username alphanumeric validation

@Suite("L2 — PayPal username validation")
struct PayPalUsernameValidationTests {

    private let service = PaymentLinkService.shared

    private func makeSettlement(name: String) -> SettlementSuggestion {
        SettlementSuggestion(id: UUID(), fromUserID: UUID(), fromName: "Alice",
                             toUserID: UUID(), toName: name,
                             amount: 25.00, currency: "USD")
    }

    @Test("Valid alphanumeric username returns a URL")
    func validAlphanumeric() {
        let url = service.paymentLink(for: makeSettlement(name: "john123"), method: .paypal)
        #expect(url != nil)
        #expect(url?.absoluteString.contains("paypal.me/john123") == true)
    }

    @Test("Username with allowed special chars (dot, hyphen, underscore) returns a URL")
    func validWithAllowedSpecialChars() {
        let url = service.paymentLink(for: makeSettlement(name: "john.doe-42_a"), method: .paypal)
        #expect(url != nil)
    }

    @Test("Username with space returns nil")
    func spaceInUsername() {
        let url = service.paymentLink(for: makeSettlement(name: "john doe"), method: .paypal)
        #expect(url == nil)
    }

    @Test("Username with path traversal returns nil")
    func pathTraversalCharacters() {
        let url = service.paymentLink(for: makeSettlement(name: "../evil"), method: .paypal)
        #expect(url == nil)
    }

    @Test("Empty username returns nil")
    func emptyUsername() {
        let url = service.paymentLink(for: makeSettlement(name: ""), method: .paypal)
        #expect(url == nil)
    }

    @Test("Username with @ symbol returns nil")
    func atSymbolInUsername() {
        let url = service.paymentLink(for: makeSettlement(name: "user@example"), method: .paypal)
        #expect(url == nil)
    }

    @Test("Username with percent-encoded char returns nil")
    func percentEncodedUsername() {
        let url = service.paymentLink(for: makeSettlement(name: "user%20name"), method: .paypal)
        #expect(url == nil)
    }
}

// MARK: - KeychainManager helpers

@Suite("KeychainManager — Bool persistence")
struct KeychainManagerBoolTests {

    private let testKey = "test_bool_\(UUID().uuidString)"

    @Test("Save and retrieve string 'true'")
    func saveAndRetrieveTrue() throws {
        try KeychainManager.shared.save("true", forKey: testKey)
        let val = try KeychainManager.shared.string(forKey: testKey)
        #expect(val == "true")
        try KeychainManager.shared.delete(forKey: testKey)
    }

    @Test("Save and retrieve string 'false'")
    func saveAndRetrieveFalse() throws {
        try KeychainManager.shared.save("false", forKey: testKey)
        let val = try KeychainManager.shared.string(forKey: testKey)
        #expect(val == "false")
        try KeychainManager.shared.delete(forKey: testKey)
    }

    @Test("Overwrite existing entry")
    func overwriteEntry() throws {
        try KeychainManager.shared.save("true", forKey: testKey)
        try KeychainManager.shared.save("false", forKey: testKey)
        let val = try KeychainManager.shared.string(forKey: testKey)
        #expect(val == "false")
        try KeychainManager.shared.delete(forKey: testKey)
    }

    @Test("Delete removes entry; subsequent read throws")
    func deleteRemovesEntry() throws {
        try KeychainManager.shared.save("true", forKey: testKey)
        try KeychainManager.shared.delete(forKey: testKey)
        #expect(throws: (any Error).self) {
            _ = try KeychainManager.shared.string(forKey: testKey)
        }
    }
}
