//
//  XBillShortcuts.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  Registers spoken phrases for xBill's intents. This is the piece that actually surfaces them —
//  an `AppIntent` alone is invocable from the Shortcuts app, but only an `AppShortcutsProvider`
//  puts it in **Siri, Spotlight, the Action Button and Apple Intelligence** without the user
//  building a shortcut by hand.
//
//  ⚠️ Every phrase must contain `\(.applicationName)`. Apple requires it, and a phrase without it
//  is dropped silently at runtime — the shortcut simply never appears, with no error anywhere.
//

import AppIntents

struct XBillShortcuts: AppShortcutsProvider {

    /// Apple caps this at 10 shortcuts. Ordering matters: the first is what Spotlight surfaces
    /// most prominently.
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckBalanceIntent(),
            phrases: [
                "What do I owe in \(.applicationName)",
                "Check my \(.applicationName) balance",
                "Am I settled up in \(.applicationName)",
                "\(.applicationName) balance"
            ],
            shortTitle: "Check Balance",
            systemImageName: "arrow.left.arrow.right.circle.fill"
        )
    }
}
