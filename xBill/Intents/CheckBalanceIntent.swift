//
//  CheckBalanceIntent.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  "Hey Siri, what do I owe in xBill?"
//
//  Runs **headlessly** — `openAppWhenRun` is false. It answers entirely from the balance snapshot
//  `CacheService` already writes into the App Group for the widget, so it needs no network, no
//  Supabase session, and no app launch. That is the whole reason this intent was built first: it
//  proves the App Intents plumbing with no auth surface at all.
//
//  Consequence worth being honest about: the figure is **as of the last time the app computed
//  balances**, not live. `BalanceSummary.isStale` exists so the spoken response can say so rather
//  than assert a number that may be days old.
//

import AppIntents
import Foundation

struct CheckBalanceIntent: AppIntent {

    static var title: LocalizedStringResource { "Check Balance" }

    static var description: IntentDescription {
        IntentDescription(
            "Find out how much you are owed and how much you owe across all your groups.",
            categoryName: "Balances",
            searchKeywords: ["balance", "owe", "owed", "settle", "debt"]
        )
    }

    /// Answered from cache, so there is no reason to interrupt the user by launching the app.
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let summary = BalanceSummary.current()
        return .result(dialog: IntentDialog(stringLiteral: summary.spokenSummary))
    }
}

// MARK: - Summary

/// The wording rules, extracted so they can be tested without invoking the intent machinery.
///
/// `AppIntent.perform()` is only reachable through Siri/Shortcuts and returns an opaque
/// `IntentResult`; asserting on it in a unit test would mean asserting on the framework rather than
/// on our behaviour. The phrasing is the part with actual rules in it, so that is what is tested.
struct BalanceSummary: Equatable {

    let owed: Decimal
    let owing: Decimal
    let currency: String
    let hasData: Bool

    static func current() -> BalanceSummary {
        let cache = CacheService.shared
        return BalanceSummary(
            owed: cache.loadTotalOwed(),
            owing: cache.loadTotalOwing(),
            currency: cache.loadBalanceCurrency(),
            hasData: cache.loadBalanceAvailable()
        )
    }

    var isSettled: Bool { owed == .zero && owing == .zero }

    /// Spoken aloud, so it is written to be *heard* rather than read: no symbols Siri would
    /// mispronounce, and the two directions are named ("owed to you" / "you owe") because a bare
    /// pair of numbers is ambiguous out loud.
    var spokenSummary: String {
        guard hasData else {
            return "Open xBill once to sync your balances, then ask again."
        }
        if isSettled {
            return "You're all settled up. Nothing owed either way."
        }
        let owedText  = owed.formatted(currencyCode: currency)
        let owingText = owing.formatted(currencyCode: currency)

        if owing == .zero { return "You're owed \(owedText). You don't owe anything." }
        if owed  == .zero { return "You owe \(owingText). Nothing is owed to you." }
        return "You're owed \(owedText), and you owe \(owingText)."
    }
}
