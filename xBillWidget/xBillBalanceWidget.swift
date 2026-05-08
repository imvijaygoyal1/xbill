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
        let dataAvailable = defaults.object(forKey: "xbill_balance_available") != nil
        let net      = defaults.double(forKey: "xbill_net_balance")
        let owed     = defaults.double(forKey: "xbill_total_owed")
        let owing    = defaults.double(forKey: "xbill_total_owing")
        let currency = defaults.string(forKey: "xbill_balance_currency") ?? "USD"
        return BalanceEntry(date: date, netBalance: net, totalOwed: owed, totalOwing: owing,
                            currency: currency, isPositive: net >= 0, dataAvailable: dataAvailable)
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
