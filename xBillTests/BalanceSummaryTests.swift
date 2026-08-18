//
//  BalanceSummaryTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  The spoken wording behind `CheckBalanceIntent`.
//
//  ⚠️ These deliberately do **not** invoke `AppIntent.perform()`. It is reachable only through
//  Siri/Shortcuts and returns an opaque `IntentResult`; asserting on that would be asserting on
//  Apple's framework rather than on our behaviour — the same mistake as testing that a `Button`
//  calls its action. The rules live in `BalanceSummary`, so that is what is tested.
//
//  What these cannot cover: whether the intent is *registered*, whether Siri matches the phrases,
//  or whether it runs at all out of process. That needs a device. The widget shipped broken for a
//  month with 7/7 green tests for exactly this reason — an out-of-process surface is not verified
//  by unit tests.
//

import Testing
import Foundation
@testable import xBill

@Suite("Check Balance spoken summary")
struct BalanceSummaryTests {

    private func summary(owed: String, owing: String,
                         currency: String = "USD", hasData: Bool = true) -> BalanceSummary {
        BalanceSummary(owed: Decimal(string: owed)!, owing: Decimal(string: owing)!,
                       currency: currency, hasData: hasData)
    }

    // MARK: - No data

    /// Before the app has ever computed balances there is nothing to report. Saying "you're all
    /// settled" here would be a lie that sounds like good news.
    @Test("An unsynced install is told to open the app, not told it is settled")
    func noDataDoesNotClaimSettled() {
        let s = summary(owed: "0", owing: "0", hasData: false)
        #expect(s.spokenSummary.contains("Open xBill"))
        #expect(!s.spokenSummary.contains("settled"))
    }

    // MARK: - Settled

    @Test("Zero on both sides reports settled")
    func settled() {
        let s = summary(owed: "0", owing: "0")
        #expect(s.isSettled)
        #expect(s.spokenSummary.contains("settled"))
    }

    // MARK: - One-sided

    /// The one-sided cases exist because "You're owed $40, and you owe $0" is what a naive
    /// implementation says, and it is worse to listen to than the sentence it replaces.
    @Test("Owed only: does not read out a zero debt")
    func owedOnly() {
        let s = summary(owed: "40.00", owing: "0")
        #expect(s.spokenSummary.contains("owed"))
        #expect(s.spokenSummary.contains("don't owe anything"))
        #expect(!s.isSettled)
    }

    @Test("Owing only: does not read out a zero credit")
    func owingOnly() {
        let s = summary(owed: "0", owing: "12.50")
        #expect(s.spokenSummary.contains("You owe"))
        #expect(s.spokenSummary.contains("Nothing is owed to you"))
    }

    // MARK: - Both directions

    /// The direction words are the point. Two bare numbers spoken aloud are ambiguous, and this is
    /// an app about who owes whom.
    @Test("Both directions are named, not just numbered")
    func bothDirectionsNamed() {
        let s = summary(owed: "40.00", owing: "12.50")
        #expect(s.spokenSummary.contains("owed"))
        #expect(s.spokenSummary.contains("you owe"))
    }

    /// A spoken sentence must not contain a currency code the way a table cell can — this asserts
    /// the amount is formatted for the group's currency rather than assumed to be dollars.
    @Test("Amounts use the stored currency, not a hardcoded symbol")
    func honoursCurrency() {
        let usd = summary(owed: "40.00", owing: "0", currency: "USD").spokenSummary
        let eur = summary(owed: "40.00", owing: "0", currency: "EUR").spokenSummary
        #expect(usd != eur, "A EUR balance must not be spoken identically to a USD one.")
    }

    /// The other direction: a settled account with data is not the same as no data at all, and the
    /// two must not collapse into one message.
    @Test("Settled and unsynced produce different answers")
    func settledIsNotUnsynced() {
        #expect(summary(owed: "0", owing: "0", hasData: true).spokenSummary
                != summary(owed: "0", owing: "0", hasData: false).spokenSummary)
    }
}
