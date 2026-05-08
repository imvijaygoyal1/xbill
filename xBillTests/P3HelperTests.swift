//
//  P3HelperTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Testing
import Foundation
@testable import xBill

// MARK: - GreetingHelper boundary tests

@Suite("GreetingHelper — Boundaries")
struct GreetingHelperTests {

    /// Builds a fixed date at the given hour using Calendar.current so that
    /// the helper's default calendar matches the one used to construct the date.
    private func date(hour: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 1; comps.day = 1; comps.hour = hour
        return Calendar.current.date(from: comps)!
    }

    @Test("Hour 4 (before 5 AM) returns 'Welcome back'")
    func hour4WelcomeBack() {
        #expect(GreetingHelper.greeting(for: date(hour: 4)) == "Welcome back")
    }

    @Test("Hour 5 (exactly 5 AM) returns 'Good morning'")
    func hour5GoodMorning() {
        #expect(GreetingHelper.greeting(for: date(hour: 5)) == "Good morning")
    }

    @Test("Hour 11 returns 'Good morning'")
    func hour11GoodMorning() {
        #expect(GreetingHelper.greeting(for: date(hour: 11)) == "Good morning")
    }

    @Test("Hour 12 returns 'Good afternoon'")
    func hour12GoodAfternoon() {
        #expect(GreetingHelper.greeting(for: date(hour: 12)) == "Good afternoon")
    }

    @Test("Hour 16 returns 'Good afternoon'")
    func hour16GoodAfternoon() {
        #expect(GreetingHelper.greeting(for: date(hour: 16)) == "Good afternoon")
    }

    @Test("Hour 17 returns 'Good evening'")
    func hour17GoodEvening() {
        #expect(GreetingHelper.greeting(for: date(hour: 17)) == "Good evening")
    }

    @Test("Hour 21 returns 'Good evening'")
    func hour21GoodEvening() {
        #expect(GreetingHelper.greeting(for: date(hour: 21)) == "Good evening")
    }

    @Test("Hour 22 (after 21) returns 'Welcome back'")
    func hour22WelcomeBack() {
        #expect(GreetingHelper.greeting(for: date(hour: 22)) == "Welcome back")
    }
}

// MARK: - BalanceMessageHelper boundary tests

@Suite("BalanceMessageHelper — Boundaries")
struct BalanceMessageHelperTests {

    @Test("Zero balance returns 'All settled. Nice!'")
    func zeroBalance() {
        #expect(BalanceMessageHelper.message(for: .zero) == "All settled. Nice!")
    }

    @Test("Positive balance of 1 returns 'You're owed money'")
    func positiveBalance() {
        #expect(BalanceMessageHelper.message(for: Decimal(1)) == "You're owed money")
    }

    @Test("Negative balance of -1 returns 'You've got balances to settle'")
    func negativeBalance() {
        #expect(BalanceMessageHelper.message(for: Decimal(-1)) == "You've got balances to settle")
    }

    @Test("Small positive balance (0.001) returns 'You're owed money'")
    func smallPositiveBalance() {
        #expect(BalanceMessageHelper.message(for: Decimal(string: "0.001")!) == "You're owed money")
    }

    @Test("Small negative balance (-0.001) returns 'You've got balances to settle'")
    func smallNegativeBalance() {
        #expect(BalanceMessageHelper.message(for: Decimal(string: "-0.001")!) == "You've got balances to settle")
    }
}
