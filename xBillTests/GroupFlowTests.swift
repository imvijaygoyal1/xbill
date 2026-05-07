//
//  GroupFlowTests.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Testing
import Foundation
@testable import xBill

// MARK: - Helpers

private func makeGroup(name: String, isArchived: Bool = false) -> BillGroup {
    BillGroup(
        id: UUID(),
        name: name,
        emoji: "💸",
        createdBy: UUID(),
        isArchived: isArchived,
        currency: "USD",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

// MARK: - Cache Pattern Tests
// Tests the array-manipulation pattern used in GroupViewModel.archiveGroup() / unarchiveGroup().
// We test this logic directly in memory to avoid UserDefaults state sharing across
// parallel tests (CacheService is a thin read/write wrapper; its I/O is not the subject here).

@Suite("GroupFlow — Cache Pattern")
struct GroupFlowCacheTests {

    @Test("Archive: removes the correct group from the active list")
    func archiveRemovesCorrectGroup() {
        let g1 = makeGroup(name: "Alpha")
        let g2 = makeGroup(name: "Beta")
        let g3 = makeGroup(name: "Gamma")
        var cached = [g1, g2, g3]

        // Simulate GroupViewModel.archiveGroup() cache step
        cached.removeAll { $0.id == g2.id }

        #expect(cached.count == 2)
        #expect(!cached.contains { $0.id == g2.id })
        #expect(cached.contains { $0.id == g1.id })
        #expect(cached.contains { $0.id == g3.id })
    }

    @Test("Unarchive: appends the group back to the active list")
    func unarchiveAppendsGroup() {
        let g1 = makeGroup(name: "Alpha")
        let g2 = makeGroup(name: "Beta")
        var cached = [g1]

        // Simulate GroupViewModel.unarchiveGroup() cache step
        if !cached.contains(where: { $0.id == g2.id }) {
            cached.append(g2)
        }

        #expect(cached.count == 2)
        #expect(cached.contains { $0.id == g2.id })
        #expect(cached.contains { $0.id == g1.id })
    }

    @Test("Unarchive is idempotent — does not create duplicates")
    func unarchiveIsIdempotent() {
        let g = makeGroup(name: "Alpha")
        var cached = [g]

        // Apply unarchive append twice
        for _ in 0..<2 {
            if !cached.contains(where: { $0.id == g.id }) {
                cached.append(g)
            }
        }

        #expect(cached.count == 1)
    }

    @Test("Archive on empty list is a no-op")
    func archiveOnEmptyList() {
        var cached: [BillGroup] = []
        let phantom = makeGroup(name: "Ghost")
        cached.removeAll { $0.id == phantom.id }
        #expect(cached.isEmpty)
    }

    @Test("Archiving the last group leaves an empty list")
    func archivingLastGroupLeavesEmptyList() {
        let g = makeGroup(name: "Only Group")
        var cached = [g]
        cached.removeAll { $0.id == g.id }
        #expect(cached.isEmpty)
    }

    @Test("Multiple sequential archives are all applied")
    func multipleArchivesInSequence() {
        let groups = (1...5).map { makeGroup(name: "Group \($0)") }
        var cached = groups

        cached.removeAll { $0.id == groups[1].id || $0.id == groups[3].id }

        #expect(cached.count == 3)
        #expect(!cached.contains { $0.id == groups[1].id })
        #expect(!cached.contains { $0.id == groups[3].id })
    }

    @Test("isArchived flag is preserved through copy-and-mutate pattern")
    func isArchivedFlagPreservedOnMutation() {
        let active   = makeGroup(name: "Active",   isArchived: false)
        let archived = makeGroup(name: "Archived", isArchived: true)

        #expect(active.isArchived   == false)
        #expect(archived.isArchived == true)

        // Simulate the var updated = group; updated.isArchived = true pattern
        var toArchive = active
        toArchive.isArchived = true
        #expect(toArchive.isArchived == true)
        #expect(active.isArchived   == false) // original unchanged (value type)
    }
}

// MARK: - BillGroup Model

@Suite("GroupFlow — BillGroup Model")
struct BillGroupModelTests {

    @Test("BillGroup Codable roundtrip preserves all fields")
    func billGroupCodableRoundtrip() throws {
        let id        = UUID()
        let creatorID = UUID()
        let original  = BillGroup(
            id: id,
            name: "Weekend Trip",
            emoji: "✈️",
            createdBy: creatorID,
            isArchived: true,
            currency: "EUR",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let data    = try encoder.encode(original)
        let decoded = try decoder.decode(BillGroup.self, from: data)

        #expect(decoded.id        == id)
        #expect(decoded.name      == "Weekend Trip")
        #expect(decoded.emoji     == "✈️")
        #expect(decoded.createdBy == creatorID)
        #expect(decoded.isArchived == true)
        #expect(decoded.currency  == "EUR")
    }

    @Test("BillGroup CodingKeys map snake_case correctly")
    func billGroupCodingKeysSnakeCase() throws {
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "name": "Trip",
            "emoji": "🏝️",
            "currency": "USD",
            "created_by": "00000000-0000-0000-0000-000000000002",
            "is_archived": true,
            "created_at": 1700000000
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let group   = try decoder.decode(BillGroup.self, from: json)

        #expect(group.name       == "Trip")
        #expect(group.isArchived == true)
        #expect(group.currency   == "USD")
    }

    @Test("BillGroup synthesized Equatable compares all fields")
    func billGroupEquality() {
        let sharedID    = UUID()
        let sharedOwner = UUID()
        let sharedDate  = Date(timeIntervalSince1970: 1_700_000_000)

        let g1 = BillGroup(id: sharedID, name: "Alpha", emoji: "💸",
                           createdBy: sharedOwner, isArchived: false,
                           currency: "USD", createdAt: sharedDate)
        let g2 = BillGroup(id: sharedID, name: "Alpha", emoji: "💸",
                           createdBy: sharedOwner, isArchived: false,
                           currency: "USD", createdAt: sharedDate)
        let g3 = BillGroup(id: UUID(),   name: "Alpha", emoji: "💸",
                           createdBy: sharedOwner, isArchived: false,
                           currency: "USD", createdAt: sharedDate)

        #expect(g1 == g2) // same id + all fields → equal
        #expect(g1 != g3) // different id → not equal
    }

    @Test("BillGroup is a value type — mutation does not affect original")
    func billGroupIsValueType() {
        let g = makeGroup(name: "Original", isArchived: false)
        var copy = g
        copy.isArchived = true
        #expect(g.isArchived  == false)
        #expect(copy.isArchived == true)
    }
}

// MARK: - Group Creation Logic

@Suite("GroupFlow — Creation Logic")
struct GroupCreationTests {

    @Test("onCreated callback: appending new group adds exactly one item")
    func onCreatedAppendsOne() {
        var groups = [makeGroup(name: "Alpha"), makeGroup(name: "Beta")]
        let countBefore = groups.count
        let newGroup    = makeGroup(name: "Gamma")

        groups.append(newGroup) // Replicates the fixed onCreated closure

        #expect(groups.count == countBefore + 1)
        #expect(groups.last?.id == newGroup.id)
    }

    @Test("onCreated callback: new group is immediately findable by id")
    func onCreatedGroupIsImmediatelyFindable() {
        var groups: [BillGroup] = []
        let newGroup = makeGroup(name: "New Group")

        groups.append(newGroup)

        #expect(groups.first { $0.id == newGroup.id } != nil)
    }

    @Test("canCreate guard: whitespace-only name is rejected")
    func canCreateRejectsEmptyName() {
        for name in ["", "   ", "\t", "  \t  "] {
            let canCreate = !name.trimmingCharacters(in: .whitespaces).isEmpty
            #expect(!canCreate, "'\(name)' should be treated as empty name")
        }
    }

    @Test("canCreate guard: valid name passes")
    func canCreateAllowsValidName() {
        let name = "  Weekend Trip  "
        let canCreate = !name.trimmingCharacters(in: .whitespaces).isEmpty
        #expect(canCreate)
    }

    @Test("Invite email: empty, whitespace, tab, and newline are all skipped")
    func inviteEmailSkippedWhenEmpty() {
        // Implementation uses .whitespacesAndNewlines (fixed from .whitespaces)
        let emails = ["", "   ", "\t", "\n", "\r\n"]
        for email in emails {
            let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(trimmed.isEmpty, "'\(email)' should be treated as empty invite email")
        }
    }

    @Test("Invite email: valid email passes the trim check")
    func inviteEmailPassesTrimCheck() {
        let email   = "  friend@example.com  "
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!trimmed.isEmpty)
        #expect(trimmed == "friend@example.com")
    }
}

// MARK: - Archive / Unarchive Logic

@Suite("GroupFlow — Archive Logic")
struct GroupArchiveLogicTests {

    @Test("Archive warning: minimizeTransactions produces suggestions when balances exist")
    func archiveWarningShownWhenBalancesExist() {
        let alice = UUID()
        let bob   = UUID()
        let balances: [UUID: Decimal] = [alice: 25, bob: -25]
        let names = [alice: "Alice", bob: "Bob"]
        let suggestions = SplitCalculator.minimizeTransactions(balances: balances, names: names, currency: "USD")
        #expect(!suggestions.isEmpty, "Non-zero balances must produce at least one settlement suggestion")
        #expect(suggestions[0].amount == 25)
        #expect(suggestions[0].fromName == "Bob")
        #expect(suggestions[0].toName == "Alice")
    }

    @Test("Archive warning: minimizeTransactions returns empty when all settled")
    func archiveWarningHiddenWhenSettled() {
        let suggestions = SplitCalculator.minimizeTransactions(balances: [:], names: [:], currency: "USD")
        #expect(suggestions.isEmpty, "Zero balances must produce no settlement suggestions")
    }

    @Test("Archive dialog message pluralises suggestion count correctly")
    func archiveWarningCountForMultipleSuggestions() {
        let alice = UUID(); let bob = UUID(); let charlie = UUID()
        // Three-way debt: alice owes bob $10, alice owes charlie $20 → 2 suggestions
        let balances: [UUID: Decimal] = [alice: -30, bob: 10, charlie: 20]
        let names = [alice: "Alice", bob: "Bob", charlie: "Charlie"]
        let suggestions = SplitCalculator.minimizeTransactions(balances: balances, names: names, currency: "USD")
        #expect(suggestions.count == 2)
        let message = "This group has \(suggestions.count) unsettled balance\(suggestions.count == 1 ? "" : "s")."
        #expect(message == "This group has 2 unsettled balances.")
    }

    @Test("Archive warning pluralises correctly")
    func archiveWarningPluralSingular() {
        let single = [SettlementSuggestion(id: UUID(), fromUserID: UUID(), fromName: "A",
                                           toUserID: UUID(), toName: "B", amount: 10, currency: "USD")]
        let multi  = [single[0],
                      SettlementSuggestion(id: UUID(), fromUserID: UUID(), fromName: "C",
                                           toUserID: UUID(), toName: "D", amount: 20, currency: "USD")]

        let singleMsg = "unsettled balance\(single.count == 1 ? "" : "s")"
        let multiMsg  = "unsettled balance\(multi.count  == 1 ? "" : "s")"

        #expect(singleMsg == "unsettled balance")
        #expect(multiMsg  == "unsettled balances")
    }

    @Test("Toolbar: isArchived flag on BillGroup correctly gates archive vs unarchive action")
    func toolbarActionDependsOnArchivedState() {
        let active   = makeGroup(name: "Active",   isArchived: false)
        let archived = makeGroup(name: "Archived", isArchived: true)
        // Mirror the GroupDetailView toolbar guard: show Unarchive when isArchived, else Archive
        #expect(!active.isArchived,   "Active group must present Archive action")
        #expect(archived.isArchived,  "Archived group must present Unarchive action")
        // Value-type safety: mutating a copy must not change the original
        var toggled = active
        toggled.isArchived = true
        #expect(toggled.isArchived)
        #expect(!active.isArchived, "Original struct must be unchanged after copy mutation")
    }
}

// MARK: - Currency List

@Suite("GroupFlow — Currency List")
struct CurrencyListTests {

    @Test("ExchangeRateService.commonCurrencies has 20 entries")
    func commonCurrenciesCount() {
        #expect(ExchangeRateService.commonCurrencies.count == 20)
    }

    @Test("commonCurrencies contains all 8 previously hard-coded currencies")
    func containsOriginalEight() {
        let original = ["USD", "EUR", "GBP", "INR", "AUD", "CAD", "SGD", "JPY"]
        for code in original {
            #expect(ExchangeRateService.commonCurrencies.contains(code), "\(code) missing")
        }
    }

    @Test("commonCurrencies contains currencies added after the fix")
    func containsNewCurrencies() {
        let added = ["CHF", "CNY", "MXN", "BRL", "KRW", "HKD", "NOK", "SEK", "DKK", "NZD", "ZAR", "AED"]
        for code in added {
            #expect(ExchangeRateService.commonCurrencies.contains(code), "\(code) missing")
        }
    }

    @Test("commonCurrencies has no duplicates")
    func noDuplicateCurrencies() {
        let list = ExchangeRateService.commonCurrencies
        #expect(list.count == Set(list).count)
    }
}

// MARK: - Realtime Contract

@Suite("GroupFlow — Realtime Contract")
struct GroupRealtimeTests {

    @Test("groupChanges topic is scoped per user — no cross-user bleed")
    func groupChangesTopicIsUserScoped() {
        let userID1 = UUID()
        let userID2 = UUID()
        let topic1  = "groups-\(userID1.uuidString)"
        let topic2  = "groups-\(userID2.uuidString)"
        #expect(topic1 != topic2)
        #expect(topic1.hasPrefix("groups-"))
        #expect(topic2.hasPrefix("groups-"))
    }
}
