//
//  ReviewPromptService.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import Observation

// MARK: - Policy

/// Decides *whether* to ask for an App Store review.
///
/// Pure and dependency-free on purpose. `requestReview` hands the decision to StoreKit, which may
/// silently show nothing — the app cannot observe the outcome, so the only part worth testing is
/// the rule that leads up to it. Extracting it as a value type rather than a seam means a test
/// cannot reach StoreKit at all, which is the same reasoning behind `IOUService.validateParties`
/// and `ProfileViewModel.validatedDisplayName`.
struct ReviewPromptPolicy {

    /// Settlements recorded before the first ask.
    ///
    /// Three, not one. Apple's rate limiter allows only **three prompts per user per year** across
    /// the whole system, so an ask spent on someone who has recorded a single payment is an ask
    /// that cannot be made later when they are demonstrably invested. Three recorded settlements
    /// means the user has completed xBill's core loop repeatedly.
    static let milestone = 3

    /// - Parameters:
    ///   - successCount: settlements this account has recorded on this device.
    ///   - lastPromptedVersion: `CFBundleShortVersionString` at the last ask, or `nil` if never.
    ///   - currentVersion: the running build's `CFBundleShortVersionString`.
    static func shouldRequest(
        successCount: Int,
        lastPromptedVersion: String?,
        currentVersion: String
    ) -> Bool {
        guard successCount >= milestone else { return false }
        // Re-asking on a later version is deliberate: someone who declined on 1.0 may feel
        // differently about 1.2. Re-asking on the *same* version is just nagging, and StoreKit
        // would swallow it anyway — burning our own signal without ever reaching the user.
        return lastPromptedVersion != currentVersion
    }
}

// MARK: - Service

/// Counts positive moments and raises `isRequestPending` when one is worth an ask.
///
/// The service never calls StoreKit. `requestReview` is only available through
/// `@Environment(\.requestReview)`, so the view owns the call and this owns the decision.
@Observable
@MainActor
final class ReviewPromptService {

    static let shared = ReviewPromptService()

    private let defaults: UserDefaults
    private let versionProvider: () -> String

    private static let countKey = "xbill_review_success_count"
    private static let versionKey = "xbill_review_last_prompted_version"

    /// True when a milestone has been reached and no ask has been made for this version yet.
    /// The view consumes it; nothing else should write to it.
    private(set) var isRequestPending = false

    init(
        defaults: UserDefaults = CacheService.defaults,
        versionProvider: @escaping () -> String = {
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        }
    ) {
        self.defaults = defaults
        self.versionProvider = versionProvider
    }

    /// Call after an action the user is likely to feel good about — a *completed* one.
    ///
    /// Deliberately not called on expense creation: adding an expense is the start of a chore,
    /// not the end of one. Recording a settlement is the moment a debt is actually closed.
    func recordPositiveEvent() {
        let count = defaults.integer(forKey: Self.countKey) + 1
        defaults.set(count, forKey: Self.countKey)

        guard ReviewPromptPolicy.shouldRequest(
            successCount: count,
            lastPromptedVersion: defaults.string(forKey: Self.versionKey),
            currentVersion: versionProvider()
        ) else { return }

        isRequestPending = true
    }

    /// Marks the ask as spent for this version. Called once the view has handed it to StoreKit —
    /// whether or not StoreKit chose to display anything, which the app cannot know.
    func consumePendingRequest() {
        isRequestPending = false
        defaults.set(versionProvider(), forKey: Self.versionKey)
    }
}
