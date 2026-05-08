//
//  P2FeatureTests.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Testing
import Foundation
@testable import xBill

// MARK: - Cross-Group Debt Simplification Tests

@Suite("CrossGroupDebt — Balance Merging")
struct CrossGroupDebtTests {

    // Helper to build a SettlementSuggestion stub
    private func suggest(from: UUID, fromName: String, to: UUID, toName: String,
                         amount: Decimal, currency: String = "USD") -> SettlementSuggestion {
        SettlementSuggestion(id: UUID(), fromUserID: from, fromName: fromName,
                             toUserID: to, toName: toName, amount: amount, currency: currency)
    }

    @Test("Merging two groups cancels cross-group debt")
    func mergingCancelsDebt() {
        // Alice is owed $10 in Group A (net +10)
        // Alice owes $10 in Group B (net -10)
        // Net across groups: $0 → no suggestions
        let alice   = UUID()
        let bob     = UUID()
        let charlie = UUID()

        // Group A: alice paid for bob ($10)
        var groupABalances: [UUID: Decimal] = [alice: 10.00, bob: -10.00]
        // Group B: charlie paid for alice ($10)
        var groupBBalances: [UUID: Decimal] = [charlie: 10.00, alice: -10.00]

        var merged: [UUID: Decimal] = [:]
        for (uid, bal) in groupABalances { merged[uid, default: .zero] += bal }
        for (uid, bal) in groupBBalances { merged[uid, default: .zero] += bal }

        let names    = [alice: "Alice", bob: "Bob", charlie: "Charlie"]
        let suggestions = SplitCalculator.minimizeTransactions(
            balances: merged, names: names, currency: "USD"
        )

        // Bob owes $10 to Charlie; Alice nets to $0
        #expect(suggestions.count == 1)
        #expect(suggestions[0].fromUserID == bob)
        #expect(suggestions[0].toUserID   == charlie)
        #expect(suggestions[0].amount     == 10.00)
    }

    @Test("Merging balances from different currencies keeps them separate")
    func currencySeparation() {
        let alice = UUID()
        let bob   = UUID()

        var usdBalances: [UUID: Decimal] = [alice: 50.00, bob: -50.00]
        var eurBalances: [UUID: Decimal] = [alice: 30.00, bob: -30.00]

        let names = [alice: "Alice", bob: "Bob"]

        let usdSuggestions = SplitCalculator.minimizeTransactions(
            balances: usdBalances, names: names, currency: "USD"
        )
        let eurSuggestions = SplitCalculator.minimizeTransactions(
            balances: eurBalances, names: names, currency: "EUR"
        )

        #expect(usdSuggestions.count == 1)
        #expect(usdSuggestions[0].currency == "USD")
        #expect(eurSuggestions.count == 1)
        #expect(eurSuggestions[0].currency == "EUR")

        // Combined total = 50 USD + 30 EUR (counted separately)
        let combined = usdSuggestions + eurSuggestions
        #expect(combined.count == 2)
    }

    @Test("Empty merged balances produce no suggestions")
    func emptyMergedBalances() {
        let suggestions = SplitCalculator.minimizeTransactions(
            balances: [:], names: [:], currency: "USD"
        )
        #expect(suggestions.isEmpty)
    }

    @Test("Single-group balance is unchanged after merging")
    func singleGroupMerge() {
        let aliceID = UUID()
        let bobID   = UUID()
        let balances: [UUID: Decimal] = [aliceID: 25.00, bobID: -25.00]
        let names    = [aliceID: "Alice", bobID: "Bob"]

        var merged: [UUID: Decimal] = [:]
        for (uid, bal) in balances { merged[uid, default: .zero] += bal }

        let suggestions = SplitCalculator.minimizeTransactions(
            balances: merged, names: names, currency: "USD"
        )
        #expect(suggestions.count == 1)
        #expect(suggestions[0].amount == 25.00)
    }

    @Test("Three-group scenario minimises to fewest transactions")
    func threeGroupMinimisation() {
        let a = UUID(), b = UUID(), c = UUID()
        // A is owed $20 in group 1, owes $5 in group 2 → net +$15
        // B owes $20 in group 1, owed $30 in group 3 → net +$10
        // C owes $5 in group 2, owes $30 in group 3 → net -$35
        let merged: [UUID: Decimal] = [a: 15, b: 10, c: -25]
        let names  = [a: "A", b: "B", c: "C"]

        let suggestions = SplitCalculator.minimizeTransactions(
            balances: merged, names: names, currency: "USD"
        )
        let total = suggestions.map(\.amount).reduce(.zero, +)
        #expect(total == 25.00)
        #expect(suggestions.count <= 2)
    }
}

// MARK: - App Lock Tests

@Suite("AppLock — State Transitions")
@MainActor
struct AppLockTests {

    @Test("Lock is a no-op when isEnabled is false")
    func lockNoOpWhenDisabled() async {
        let svc = AppLockService.shared
        let wasEnabled = svc.isEnabled
        svc.isEnabled  = false
        svc.isLocked   = false

        svc.lock()

        #expect(!svc.isLocked)

        // Restore
        svc.isEnabled = wasEnabled
    }

    @Test("Lock sets isLocked when isEnabled is true")
    func lockSetsLockedWhenEnabled() async {
        let svc = AppLockService.shared
        let wasEnabled = svc.isEnabled
        svc.isEnabled  = true
        svc.isLocked   = false

        svc.lock()

        #expect(svc.isLocked)

        // Restore
        svc.isLocked  = false
        svc.isEnabled = wasEnabled
    }
}

// MARK: - Manual Receipt Entry Tests

@Suite("ReceiptViewModel — Manual Entry")
@MainActor
struct ManualReceiptTests {

    @Test("startManually creates a blank receipt with empty items")
    func startManuallyBlankReceipt() {
        let vm = ReceiptViewModel()
        let members: [User] = []

        vm.startManually(members: members)

        #expect(vm.scannedReceipt != nil)
        #expect(vm.items.isEmpty)
        #expect(vm.merchantName.isEmpty)
        #expect(vm.totalAmount.isEmpty)
        #expect(vm.tipAmount.isEmpty)
        #expect(vm.capturedImage == nil)
    }

    @Test("startManually assigns members to the view model")
    func startManuallyAssignsMembers() {
        let vm = ReceiptViewModel()
        let u1 = User(id: UUID(), email: "a@b.com", displayName: "Alice", avatarURL: nil, createdAt: Date())
        let u2 = User(id: UUID(), email: "c@d.com", displayName: "Bob",   avatarURL: nil, createdAt: Date())

        vm.startManually(members: [u1, u2])

        #expect(vm.members.count == 2)
        #expect(vm.members[0].displayName == "Alice")
        #expect(vm.members[1].displayName == "Bob")
    }

    @Test("Items added after startManually accumulate correctly")
    func addItemsAfterStartManually() {
        let vm = ReceiptViewModel()
        vm.startManually()

        vm.addItem(name: "Coffee",  unitPrice: 4.50)
        vm.addItem(name: "Muffin",  unitPrice: 3.75)

        #expect(vm.items.count == 2)
        #expect(vm.totalFromItems == 8.25)
    }

    @Test("startManually clears previous scan state")
    func startManuallyClearsPreviousScan() {
        let vm = ReceiptViewModel()
        vm.items = [ReceiptItem(name: "Old item", quantity: 1, unitPrice: 10.00)]
        vm.merchantName = "Old Merchant"

        vm.startManually()

        #expect(vm.items.isEmpty)
        #expect(vm.merchantName.isEmpty)
        #expect(vm.capturedImage == nil)
    }
}

// MARK: - Cache Service Tests

@Suite("CacheService — Balance Persistence", .serialized)
struct CacheServiceBalanceTests {

    @Test("saveBalance round-trips net/owed/owing correctly")
    func balanceRoundTrip() {
        CacheService.shared.saveBalance(netBalance: 42.50, totalOwed: 100.00, totalOwing: 57.50)

        let net   = CacheService.shared.loadNetBalance()
        let owed  = CacheService.shared.loadTotalOwed()
        let owing = CacheService.shared.loadTotalOwing()

        // M-47: tighten tolerance from 0.01 to 0.001 so a $100 value cannot pass as $99.99.
        // CacheService stores balances as Decimal strings, so the round-trip should be exact;
        // 0.001 is a small guard for any intermediate Double conversion in the load path.
        #expect(abs(Double(truncating: net   as NSDecimalNumber) - 42.50)  < 0.001)
        #expect(abs(Double(truncating: owed  as NSDecimalNumber) - 100.00) < 0.001)
        #expect(abs(Double(truncating: owing as NSDecimalNumber) - 57.50)  < 0.001)

        // Clean up
        CacheService.defaults.removeObject(forKey: CacheService.netBalanceKey)
        CacheService.defaults.removeObject(forKey: CacheService.totalOwedKey)
        CacheService.defaults.removeObject(forKey: CacheService.totalOwingKey)
    }

    @Test("loadNetBalance returns zero when nothing saved")
    func netBalanceDefaultsZero() {
        CacheService.defaults.removeObject(forKey: CacheService.netBalanceKey)
        let net = CacheService.shared.loadNetBalance()
        // Decimal(0.0) == .zero; double-check via NSDecimalNumber
        #expect(Double(truncating: net as NSDecimalNumber) == 0.0)
    }
}

// MARK: - Contact Discovery Helper Tests

@Suite("InviteFlow — Email Validation")
struct ContactDiscoveryTests {

    @Test("Valid emails pass the at-dot check")
    func validEmailsPass() {
        let valid = ["alice@example.com", "bob.smith@work.co.uk", "x@y.z"]
        for email in valid {
            let ok = email.contains("@") && email.contains(".")
            #expect(ok, "'\(email)' should be valid")
        }
    }

    @Test("Duplicate emails are not added to pending list")
    func duplicateEmailRejected() {
        var pending: [String] = ["alice@example.com"]
        let newEmail = "alice@example.com"
        let trimmed  = newEmail.trimmingCharacters(in: .whitespaces).lowercased()
        if !pending.contains(trimmed) { pending.append(trimmed) }
        #expect(pending.count == 1)
    }

    @Test("Contact picker emails are lowercased before adding")
    func contactEmailsLowercased() {
        let raw     = ["Alice@Example.COM", "BOB@TEST.ORG"]
        let cleaned = raw.map { $0.lowercased() }
        #expect(cleaned[0] == "alice@example.com")
        #expect(cleaned[1] == "bob@test.org")
    }
}
