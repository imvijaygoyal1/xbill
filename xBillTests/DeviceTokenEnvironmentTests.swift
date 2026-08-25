//
//  DeviceTokenEnvironmentTests.swift
//  xBillTests
//
//  PUSH-02. Push notifications were not delivered because the APNs host was chosen from the
//  **sender's** build (`#if DEBUG`) while sandbox-vs-production is a property of the
//  **recipient's token**. `device_tokens` recorded no environment, so correct routing was
//  impossible even in principle.
//
//  What can be tested here is the client's half: that the row this app writes actually carries
//  the environment, under the key the column is named, with a value the CHECK constraint accepts.
//
//  What CANNOT be tested here, and must not be claimed from a green run:
//    • that a notification arrives. APNs does not deliver to a simulator, and no test in this
//      project can reach it.
//    • that the four Edge Functions route per token. That is TypeScript with no local runtime;
//      it is verified by invoking the deployed function and reading its report.
//

import Testing
import Foundation
@testable import xBill

@Suite("PUSH-02/03 — device token environment and scope", .serialized)
struct DeviceTokenEnvironmentTests {

    /// Decode the row the way PostgREST receives it: through the encoder the transport really
    /// uses, not one constructed here. `SPLIT-04` passed every server-side check and still failed
    /// in production because the test encoded a payload by hand.
    private func encoded(_ row: AuthService.DeviceTokenRow) throws -> [String: Any] {
        let data = try SupabaseManager.postgrestEncoder.encode(row)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("the written row carries an environment under the column's own name")
    func environmentIsOnTheWire() throws {
        let row = AuthService.DeviceTokenRow(
            userID: UUID(uuidString: "D58C8C51-1150-4F5D-AD1D-DB0A92D9ECA9")!,
            token: String(repeating: "a", count: 64),
            platform: "apns",
            environment: "sandbox"
        )
        let json = try encoded(row)

        // The key name is the whole point. `environment` missing — or spelled `env` — is not an
        // error: the column defaults to 'production' and a sandbox device goes quiet forever.
        #expect(json["environment"] as? String == "sandbox")
        #expect(json["user_id"] as? String == "D58C8C51-1150-4F5D-AD1D-DB0A92D9ECA9")
        #expect(json["platform"] as? String == "apns")

        // Exactly the four columns the upsert is meant to write, and no others. An unexpected key
        // is a PostgREST error on a path with no user-visible failure mode.
        #expect(Set(json.keys) == ["user_id", "token", "platform", "environment"])
    }

    @Test("both environments survive encoding unchanged")
    func bothEnvironmentsRoundTrip() throws {
        for value in ["sandbox", "production"] {
            let row = AuthService.DeviceTokenRow(userID: UUID(), token: "t",
                                                 platform: "apns", environment: value)
            #expect(try encoded(row)["environment"] as? String == value)
        }
    }

    /// Migration 048 constrains the column to exactly these two values, and `apnsHost()` falls
    /// back to production for anything else — so a third spelling would be a silent misroute.
    @Test("this build reports an environment the CHECK constraint accepts")
    func buildEnvironmentIsValid() {
        #expect(["sandbox", "production"].contains(AuthService.apnsEnvironment))
    }

    /// The mapping itself, asserted in the direction this build can observe.
    ///
    /// A test target is compiled Debug, so it sees the same branch the app does — and Debug is
    /// signed with `xBill.Debug.entitlements`, which declares `aps-environment: development`.
    /// Release is signed with `xBill.entitlements` (`production`); that branch is verified by the
    /// archive check in `RELEASE_VERIFICATION.md`, not here.
    @Test("a Debug build registers as sandbox, matching its entitlement")
    func debugRegistersAsSandbox() {
        #if DEBUG
        #expect(AuthService.apnsEnvironment == "sandbox")
        #else
        #expect(AuthService.apnsEnvironment == "production")
        #endif
    }

    // MARK: - PUSH-03 — token cleanup is scoped to this device

    /// The fallback is the risky half. Getting it backwards means a user who revokes notification
    /// permission keeps receiving pushes, which is the privacy defect `MINOR-01` already fixed
    /// once — so it is asserted in both directions rather than assumed.
    @Test("with no remembered token, cleanup falls back to the user's whole set")
    func cleanupFallsBackWhenTokenUnknown() {
        #expect(AuthService.cleanupScope(lastRegistered: nil) == .allDevicesForUser)
        #expect(AuthService.cleanupScope(lastRegistered: "") == .allDevicesForUser)
    }

    @Test("with a remembered token, cleanup names only this device")
    func cleanupScopesToThisDevice() {
        let token = String(repeating: "b", count: 64)
        #expect(AuthService.cleanupScope(lastRegistered: token) == .thisDevice(token))
    }

    /// Asserts the memory that makes "this device" expressible at all.
    ///
    /// It does **not** assert that `updateDeviceToken` stopped deleting sibling rows — that is a
    /// PostgREST call this suite cannot make, and claiming it from here would be exactly the kind
    /// of over-broad coverage claim `UI-01` produced. It is verified by reading the method and by
    /// two devices staying registered on hardware.
    @Test("the remembered token round-trips and clears")
    func rememberedTokenRoundTrips() {
        let key = AuthService.lastRegisteredTokenKey
        let saved = CacheService.defaults.string(forKey: key)
        defer {
            if let saved { CacheService.defaults.set(saved, forKey: key) }
            else { CacheService.defaults.removeObject(forKey: key) }
        }

        AuthService.lastRegisteredAPNsToken = "token-one"
        #expect(AuthService.lastRegisteredAPNsToken == "token-one")
        AuthService.lastRegisteredAPNsToken = "token-two"
        #expect(AuthService.lastRegisteredAPNsToken == "token-two")
        AuthService.lastRegisteredAPNsToken = nil
        #expect(AuthService.lastRegisteredAPNsToken == nil)
        #expect(AuthService.cleanupScope(lastRegistered: AuthService.lastRegisteredAPNsToken)
                == .allDevicesForUser)
    }
}
