//
//  GroupEntity.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  Lets Siri, Shortcuts and Spotlight resolve a spoken group name — "Tokyo Trip" — to a real
//  group. Every other intent that needs a group depends on this one.
//
//  Backed by `CacheService`, which already mirrors groups into the App Group container for the
//  widget. That is deliberate and load-bearing: an intent may run **out of process**, and xBill's
//  Supabase session lives in a Keychain item with no shared access group, so an intent cannot
//  authenticate or reach the network. Reads come from the cache; anything that *writes* must open
//  the app instead.
//

import AppIntents
import Foundation

struct GroupEntity: AppEntity {

    let id: UUID
    let name: String
    let emoji: String
    let currency: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Group" }

    var displayRepresentation: DisplayRepresentation {
        // The emoji goes in the title rather than a subtitle so it survives Siri's compact
        // disambiguation list, where subtitles are frequently dropped.
        DisplayRepresentation(
            title: "\(emoji) \(name)",
            subtitle: "\(currency)"
        )
    }

    static var defaultQuery: GroupQuery { GroupQuery() }

    init(id: UUID, name: String, emoji: String, currency: String) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.currency = currency
    }

    init(_ group: BillGroup) {
        self.init(id: group.id, name: group.name, emoji: group.emoji, currency: group.currency)
    }
}

// MARK: - Query

struct GroupQuery: EntityQuery {

    /// Archived groups are excluded everywhere. A user saying "add to Tokyo Trip" about a trip they
    /// archived last year means the active one, and offering an archived group leads to an expense
    /// filed somewhere they will not look for it.
    private func activeGroups() -> [BillGroup] {
        CacheService.shared.loadGroups().filter { !$0.isArchived }
    }

    func entities(for identifiers: [UUID]) async throws -> [GroupEntity] {
        let wanted = Set(identifiers)
        return activeGroups().filter { wanted.contains($0.id) }.map(GroupEntity.init)
    }

    func suggestedEntities() async throws -> [GroupEntity] {
        activeGroups().map(GroupEntity.init)
    }
}

extension GroupQuery: EntityStringQuery {

    /// Matches what a person would actually say. Siri hands over a transcription, so this is
    /// deliberately forgiving: case-insensitive, diacritic-insensitive, and substring rather than
    /// prefix — "tokyo" should find "Tokyo Trip 2026".
    func entities(matching string: String) async throws -> [GroupEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return activeGroups()
            .filter { $0.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            .map(GroupEntity.init)
    }
}
