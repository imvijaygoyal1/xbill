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

@Suite("PUSH-02 — device token environment")
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
}
