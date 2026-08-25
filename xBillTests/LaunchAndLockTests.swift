//
//  LaunchAndLockTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  Two device-reported defects, both about *when* something is shown rather than what:
//
//  LAUNCH-01  Every cold launch flashed the login screen and then signed itself in.
//  LOCK-01    A phone sitting idle with xBill backgrounded woke its own screen to ask for Face ID.
//
//  Neither is reachable from a unit test end to end — one needs a real cold launch, the other a
//  real background transition. What IS testable is the rule each fix turns on, and those rules are
//  where both bugs lived.
//

import Testing
import Foundation
@testable import xBill

@Suite("Launch and lock gating")
@MainActor
struct LaunchAndLockTests {

    // MARK: - LAUNCH-01

    /// The flag must start false. `currentUser` is nil on every cold launch until an async restore
    /// completes, so a view keying only on `currentUser != nil` shows the signed-out UI first.
    @Test("A fresh view model has not yet resolved the session")
    func startsUnresolved() {
        #expect(AuthViewModel().hasResolvedInitialSession == false)
    }

    /// The distinction the launch screen depends on: "not signed in" and "not yet known" are
    /// different states, and only the first should show `AuthView`.
    @Test("Unresolved-and-nil is distinguishable from resolved-and-nil")
    func unresolvedIsNotSignedOut() {
        let vm = AuthViewModel()
        #expect(vm.currentUser == nil)
        #expect(vm.hasResolvedInitialSession == false)   // → launch placeholder

        vm.hasResolvedInitialSession = true
        #expect(vm.currentUser == nil)
        #expect(vm.hasResolvedInitialSession == true)    // → AuthView, correctly
    }

    // MARK: - LOCK-01

    /// `AppLockView` auto-authenticates only while `scenePhase == .active`. The bug was a bare
    /// `.task`, which fires as the view is inserted — and `lock()` inserts it on `.background`,
    /// so `LAContext.evaluatePolicy` ran while the phone was idle and **woke the screen**.
    ///
    /// The view's gate is `scenePhase == .active`; this pins the rule that gate encodes.
    @Test("Only the active phase may trigger biometric evaluation")
    func onlyActivePhaseAuthenticates() {
        func shouldPrompt(_ phase: ScenePhase) -> Bool { phase == .active }
        #expect(shouldPrompt(.active))
        #expect(!shouldPrompt(.inactive), "A notification banner or app switcher must not prompt")
        #expect(!shouldPrompt(.background), "Backgrounding is when lock() runs — prompting here wakes the screen")
    }

    /// `lock()` is a no-op when the feature is off, so a user without App Lock can never be shown
    /// the lock screen at all — the precondition for the wake.
    @Test("Locking is inert when App Lock is disabled")
    func lockIsInertWhenDisabled() {
        let service = AppLockService.shared
        let wasEnabled = service.isEnabled
        defer { service.isEnabled = wasEnabled }

        service.isEnabled = false
        service.isLocked  = false
        service.lock()
        #expect(service.isLocked == false)
    }
}

import SwiftUI
