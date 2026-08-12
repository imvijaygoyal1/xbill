//
//  ReviewPromptPolicyTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  The rule behind the App Store review prompt.
//
//  ⚠️ Test the policy, never the service's `requestReview` path. `requestReview` hands the
//  decision to StoreKit, which may show nothing and reports no outcome — an assertion there
//  would be asserting a system decision the app cannot see. The rule is extracted as a pure
//  function precisely so a test cannot reach StoreKit at all, matching the reasoning in
//  `PreNetworkGuardTests`.
//
//  Getting this wrong is expensive in a way that is invisible: Apple allows only **three
//  prompts per user per year**, system-wide. An ask spent too early, or repeated on a version
//  the user already declined, is silently swallowed and cannot be reclaimed.
//

import Testing
import Foundation
@testable import xBill

@Suite("App Store review prompt policy")
struct ReviewPromptPolicyTests {

    private let version = "1.1"

    // MARK: - The milestone

    /// Below the milestone nothing is asked, however new the version. A user who has recorded
    /// one payment has not yet demonstrated the app works for them.
    @Test("No ask before the milestone")
    func belowMilestoneNeverAsks() {
        for count in 0 ..< ReviewPromptPolicy.milestone {
            #expect(ReviewPromptPolicy.shouldRequest(
                successCount: count, lastPromptedVersion: nil, currentVersion: version) == false,
                "Asked after only \(count) settlement(s).")
        }
    }

    /// The other half of the pair. A policy that refused everything would satisfy the test above
    /// on its own — this is what proves the prompt can ever actually fire.
    @Test("Asks once the milestone is reached, and stays true beyond it")
    func atAndAboveMilestoneAsks() {
        #expect(ReviewPromptPolicy.shouldRequest(
            successCount: ReviewPromptPolicy.milestone,
            lastPromptedVersion: nil, currentVersion: version))
        #expect(ReviewPromptPolicy.shouldRequest(
            successCount: ReviewPromptPolicy.milestone + 25,
            lastPromptedVersion: nil, currentVersion: version))
    }

    // MARK: - Version gating

    /// The nagging guard. Re-asking on a version the user already saw cannot reach them —
    /// StoreKit swallows it — so it burns the app's own signal for nothing.
    @Test("Never asks twice on the same version")
    func sameVersionIsAskedOnlyOnce() {
        #expect(ReviewPromptPolicy.shouldRequest(
            successCount: 99, lastPromptedVersion: version, currentVersion: version) == false)
    }

    /// But a later version is a fresh question: someone who declined on 1.0 may feel differently
    /// about 1.2. Without this the app would ask exactly once, ever.
    @Test("Asks again after a version update")
    func newVersionReopensTheAsk() {
        #expect(ReviewPromptPolicy.shouldRequest(
            successCount: ReviewPromptPolicy.milestone,
            lastPromptedVersion: "1.0", currentVersion: "1.1"))
    }

    /// A first run has no stored version. `nil` must read as "never asked", not as a match.
    @Test("A never-prompted install is eligible")
    func nilStoredVersionIsEligible() {
        #expect(ReviewPromptPolicy.shouldRequest(
            successCount: ReviewPromptPolicy.milestone,
            lastPromptedVersion: nil, currentVersion: version))
    }

    /// Both conditions are required, not either. A high count does not override the version
    /// gate, and a new version does not override the milestone.
    @Test("Milestone and version gate are both necessary")
    func bothConditionsRequired() {
        #expect(ReviewPromptPolicy.shouldRequest(
            successCount: 1, lastPromptedVersion: "1.0", currentVersion: version) == false)
        #expect(ReviewPromptPolicy.shouldRequest(
            successCount: 100, lastPromptedVersion: version, currentVersion: version) == false)
    }
}

@Suite("Review prompt service")
@MainActor
struct ReviewPromptServiceTests {

    /// A private suite so a test never reads or writes the real App Group counter.
    private func makeService(version: String = "1.1") -> ReviewPromptService {
        let name = "review.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return ReviewPromptService(defaults: defaults, versionProvider: { version })
    }

    @Test("The pending flag is raised only on the milestone event")
    func flagRaisesAtMilestone() {
        let service = makeService()
        for _ in 1 ..< ReviewPromptPolicy.milestone {
            service.recordPositiveEvent()
            #expect(service.isRequestPending == false)
        }
        service.recordPositiveEvent()
        #expect(service.isRequestPending)
    }

    /// Consuming must be durable. If the version were not recorded, every later settlement would
    /// re-raise the flag and the app would ask on each one — the exact behaviour StoreKit's
    /// three-per-year limit punishes.
    @Test("Consuming an ask stops it recurring on the same version")
    func consumingIsDurable() {
        let service = makeService()
        for _ in 0 ..< ReviewPromptPolicy.milestone { service.recordPositiveEvent() }
        #expect(service.isRequestPending)

        service.consumePendingRequest()
        #expect(service.isRequestPending == false)

        service.recordPositiveEvent()
        #expect(service.isRequestPending == false, "Asked again on a version already spent.")
    }
}
