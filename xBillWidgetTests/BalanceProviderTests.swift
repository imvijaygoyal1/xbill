//
//  BalanceProviderTests.swift
//  xBillWidgetTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import Testing
import WidgetKit
@testable import xBillWidgetCore

@Suite("Balance widget provider", .serialized)
struct BalanceProviderTests {

    private func defaults(name: String = UUID().uuidString) -> UserDefaults {
        let suiteName = "com.vijaygoyal.xbill.widget.tests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test("Snapshot key takes precedence over legacy balance keys")
    func snapshotKeyTakesPrecedence() throws {
        let defaults = defaults()
        let snapshot = WidgetBalanceSnapshot(
            net: "-12.50",
            owed: "8.00",
            owing: "20.50",
            currency: "EUR",
            available: true
        )
        defaults.set(try JSONEncoder().encode(snapshot), forKey: WidgetBalanceKeys.snapshot)
        defaults.set("999", forKey: WidgetBalanceKeys.legacyNet)
        defaults.set(true, forKey: WidgetBalanceKeys.legacyAvailable)

        let entry = BalanceProvider(defaults: defaults).entry(for: Date(timeIntervalSince1970: 100))

        #expect(entry.netBalance == -12.50)
        #expect(entry.totalOwed == 8.00)
        #expect(entry.totalOwing == 20.50)
        #expect(entry.currency == "EUR")
        #expect(entry.isPositive == false)
        #expect(entry.dataAvailable == true)
    }

    @Test("Legacy balance keys still produce an available entry")
    func legacyKeysProduceEntry() {
        let defaults = defaults()
        defaults.set("45.75", forKey: WidgetBalanceKeys.legacyNet)
        defaults.set("60.00", forKey: WidgetBalanceKeys.legacyOwed)
        defaults.set("14.25", forKey: WidgetBalanceKeys.legacyOwing)
        defaults.set("GBP", forKey: WidgetBalanceKeys.legacyCurrency)
        defaults.set(true, forKey: WidgetBalanceKeys.legacyAvailable)

        let entry = BalanceProvider(defaults: defaults).entry(for: Date(timeIntervalSince1970: 200))

        #expect(entry.netBalance == 45.75)
        #expect(entry.totalOwed == 60.00)
        #expect(entry.totalOwing == 14.25)
        #expect(entry.currency == "GBP")
        #expect(entry.isPositive == true)
        #expect(entry.dataAvailable == true)
    }

    @Test("Missing stored balance returns unavailable placeholder entry")
    func missingStoredBalanceReturnsUnavailableEntry() {
        let entry = BalanceProvider(defaults: defaults()).entry(for: Date(timeIntervalSince1970: 300))

        #expect(entry.netBalance == 0)
        #expect(entry.totalOwed == 0)
        #expect(entry.totalOwing == 0)
        #expect(entry.dataAvailable == false)
        #expect(entry.isPositive == true)
        #expect(entry.currency.isEmpty == false)
    }

    @Test("Invalid numeric strings fail closed to zero values")
    func invalidNumericStringsFailClosed() throws {
        let defaults = defaults()
        let snapshot = WidgetBalanceSnapshot(
            net: "not-a-number",
            owed: "also-bad",
            owing: "bad-too",
            currency: "USD",
            available: true
        )
        defaults.set(try JSONEncoder().encode(snapshot), forKey: WidgetBalanceKeys.snapshot)

        let entry = BalanceProvider(defaults: defaults).entry(for: Date())

        #expect(entry.netBalance == 0)
        #expect(entry.totalOwed == 0)
        #expect(entry.totalOwing == 0)
        #expect(entry.isPositive == true)
        #expect(entry.dataAvailable == true)
    }

    @Test("Timeline entries contain immediate, thirty minute, and hourly refresh cadence")
    func timelineEntriesContainExpectedRefreshCadence() {
        let defaults = defaults()
        let snapshot = WidgetBalanceSnapshot(
            net: "10",
            owed: "10",
            owing: "0",
            currency: "USD",
            available: true
        )
        defaults.set(try? JSONEncoder().encode(snapshot), forKey: WidgetBalanceKeys.snapshot)

        let entries = BalanceProvider(defaults: defaults)
            .timelineEntries(startingAt: Date(timeIntervalSince1970: 1_000))

        #expect(entries.count == 3)
        #expect(entries[1].date.timeIntervalSince(entries[0].date) == 30 * 60)
        #expect(entries[2].date.timeIntervalSince(entries[0].date) == 60 * 60)
    }

    @Test("Currency formatting uses full and compact money displays")
    func currencyFormatting() {
        let full = WidgetBalanceFormatting.formatted(42.5, currency: "USD")
        let short = WidgetBalanceFormatting.formattedShort(42.5, currency: "USD")

        #expect(full.contains("42.50"))
        #expect(short.contains("43") || short.contains("42"))
    }

    @Test("Widget metadata remains stable")
    func widgetMetadata() {
        let widget = xBillBalanceWidget()

        #expect(widget.kind == "xBillBalanceWidget")
    }
}
