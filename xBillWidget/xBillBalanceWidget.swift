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
    let isPositive: Bool
}

// MARK: - Timeline Provider

struct BalanceProvider: TimelineProvider {
    private let defaults = UserDefaults(suiteName: "group.com.vijaygoyal.xbill") ?? .standard

    func placeholder(in context: Context) -> BalanceEntry {
        BalanceEntry(date: Date(), netBalance: 42.50, totalOwed: 42.50, totalOwing: 0, isPositive: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (BalanceEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BalanceEntry>) -> Void) {
        let entries = [entry()]
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }

    private func entry() -> BalanceEntry {
        let net   = defaults.double(forKey: "xbill_net_balance")
        let owed  = defaults.double(forKey: "xbill_total_owed")
        let owing = defaults.double(forKey: "xbill_total_owing")
        return BalanceEntry(date: Date(), netBalance: net, totalOwed: owed,
                            totalOwing: owing, isPositive: net >= 0)
    }
}

// MARK: - Widget View

struct BalanceWidgetView: View {
    var entry: BalanceEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundStyle(entry.isPositive ? Color(red: 0.04, green: 0.54, blue: 0.32) : Color(red: 0.99, green: 0.47, blue: 0.51))
                Text("xBill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(entry.isPositive ? "Owed to you" : "You owe")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(String(format: "$%.2f", abs(entry.netBalance)))
                .font(.title2.monospacedDigit().weight(.semibold))
                .foregroundStyle(entry.isPositive
                                 ? Color(red: 0.04, green: 0.54, blue: 0.32)
                                 : Color(red: 0.99, green: 0.47, blue: 0.51))

            if entry.totalOwed > 0 && entry.totalOwing > 0 {
                HStack(spacing: 4) {
                    Label(String(format: "$%.0f", entry.totalOwed), systemImage: "arrow.down")
                        .foregroundStyle(Color(red: 0.04, green: 0.54, blue: 0.32))
                    Spacer()
                    Label(String(format: "$%.0f", entry.totalOwing), systemImage: "arrow.up")
                        .foregroundStyle(Color(red: 0.99, green: 0.47, blue: 0.51))
                }
                .font(.caption2.monospacedDigit())
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
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
