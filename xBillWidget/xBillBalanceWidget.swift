//
//  xBillBalanceWidget.swift
//  xBillWidget
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  NOTE: Requires App Group "group.com.vijaygoyal.xbill" to be registered in Apple Developer Portal.
//  Until registered, the widget reads from UserDefaults.standard (data may be stale).
//

import WidgetKit
import SwiftUI

// MARK: - Balance Snapshot (shared with CacheService)

/// Mirror of `BalanceSnapshot` in CacheService.swift.
/// Duplicated here so the widget extension compiles without importing the main app module.
private struct WidgetBalanceSnapshot: Codable {
    var net: String
    var owed: String
    var owing: String
    var currency: String
    var available: Bool
}

// MARK: - Balance Entry

struct BalanceEntry: TimelineEntry {
    let date: Date
    let netBalance: Double
    let totalOwed: Double
    let totalOwing: Double
    let currency: String
    let isPositive: Bool
    let dataAvailable: Bool
}

// MARK: - Timeline Provider

struct BalanceProvider: TimelineProvider {
    private let defaults = UserDefaults(suiteName: "group.com.vijaygoyal.xbill") ?? .standard

    /// The single-key written by CacheService.saveBalance (L-27 atomic fix).
    private let snapshotKey = "xbill_balance_snapshot"
    /// Legacy individual keys — read as fallback if the snapshot key is absent.
    private let legacyNetKey       = "xbill_net_balance"
    private let legacyOwedKey      = "xbill_total_owed"
    private let legacyOwingKey     = "xbill_total_owing"
    private let legacyCurrencyKey  = "xbill_balance_currency"
    private let legacyAvailableKey = "xbill_balance_available"

    func placeholder(in context: Context) -> BalanceEntry {
        BalanceEntry(date: Date(), netBalance: 42.50, totalOwed: 42.50, totalOwing: 0,
                     currency: "USD", isPositive: true, dataAvailable: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (BalanceEntry) -> Void) {
        completion(entry(for: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BalanceEntry>) -> Void) {
        let now = Date()
        let entries = [
            entry(for: now),
            entry(for: now.addingTimeInterval(30 * 60)),
            entry(for: now.addingTimeInterval(60 * 60)),
        ]
        // .atEnd triggers the next fetch after the last entry's date elapses.
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(for date: Date) -> BalanceEntry {
        // L-27: read from the atomic single-key snapshot; fall back to legacy keys
        // so widgets that haven't refreshed yet continue to display valid data.
        let snapshot = loadSnapshot()
        guard let snapshot else {
            return BalanceEntry(date: date, netBalance: 0, totalOwed: 0, totalOwing: 0,
                                currency: Locale.current.currency?.identifier ?? "USD",
                                isPositive: true, dataAvailable: false)
        }
        let net  = Double(snapshot.net)  ?? 0
        let owed = Double(snapshot.owed) ?? 0
        let owing = Double(snapshot.owing) ?? 0
        return BalanceEntry(date: date, netBalance: net, totalOwed: owed, totalOwing: owing,
                            currency: snapshot.currency, isPositive: net >= 0, dataAvailable: snapshot.available)
    }

    private func loadSnapshot() -> WidgetBalanceSnapshot? {
        if let data = defaults.data(forKey: snapshotKey),
           let snapshot = try? JSONDecoder().decode(WidgetBalanceSnapshot.self, from: data) {
            return snapshot
        }
        // Legacy fallback: individual keys written before L-27 fix was deployed.
        guard defaults.object(forKey: legacyAvailableKey) != nil else { return nil }
        return WidgetBalanceSnapshot(
            net: defaults.string(forKey: legacyNetKey) ?? "0",
            owed: defaults.string(forKey: legacyOwedKey) ?? "0",
            owing: defaults.string(forKey: legacyOwingKey) ?? "0",
            currency: defaults.string(forKey: legacyCurrencyKey) ?? "USD",
            available: true
        )
    }
}

// MARK: - Widget View

struct BalanceWidgetView: View {
    var entry: BalanceEntry

    private let positive = Color("MoneyPositive")
    private let negative = Color("MoneyNegative")

    var body: some View {
        if !entry.dataAvailable {
            unavailableView
        } else {
            balanceView
        }
    }

    private var unavailableView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundStyle(.secondary)
                Text("xBill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("No data yet")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Open xBill to sync your balances.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var balanceView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundStyle(entry.isPositive ? positive : negative)
                Text("xBill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(entry.isPositive ? "Owed to you" : "You owe")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(formatted(abs(entry.netBalance), currency: entry.currency))
                .font(.title2.monospacedDigit().weight(.semibold))
                .foregroundStyle(entry.isPositive ? positive : negative)

            if entry.totalOwed > 0 && entry.totalOwing > 0 {
                HStack(spacing: 4) {
                    Label(formattedShort(entry.totalOwed, currency: entry.currency), systemImage: "arrow.down")
                        .foregroundStyle(positive)
                    Spacer()
                    Label(formattedShort(entry.totalOwing, currency: entry.currency), systemImage: "arrow.up")
                        .foregroundStyle(negative)
                }
                .font(.caption2.monospacedDigit())
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func formatted(_ value: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(currency) \(String(format: "%.2f", value))"
    }

    private func formattedShort(_ value: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(currency) \(Int(value))"
    }
}

// MARK: - Widget Configuration

struct xBillBalanceWidget: Widget {
    let kind: String = "xBillBalanceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BalanceProvider()) { entry in
            BalanceWidgetView(entry: entry)
        }
        .configurationDisplayName("xBill Balance")
        .description("See your current balance across all groups at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
