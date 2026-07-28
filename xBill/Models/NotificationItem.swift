//
//  NotificationItem.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation

// MARK: - Event Type

enum NotificationEventType: String, Codable, Sendable {
    case expenseAdded
    case settlementMade
    case commentAdded
    case friendRequest
}

// MARK: - Model

struct NotificationItem: Identifiable, Sendable, Codable {
    let id: UUID
    let eventType: NotificationEventType
    let title: String
    let subtitle: String
    let amount: Decimal
    let currency: String
    let category: Expense.Category
    let createdAt: Date
    var isRead: Bool
    let groupID: UUID?
    let expenseID: UUID?
    /// True only for rows that exist in `public.notifications`.
    ///
    /// The Activity list also shows historical expense-derived rows for accounts that
    /// predate migration 040. Those carry an *expense* id, so a read/unread PATCH against
    /// the notifications table matches zero rows. Read state for them is local-only.
    let isServerBacked: Bool

    init(
        id: UUID,
        eventType: NotificationEventType,
        title: String,
        subtitle: String,
        amount: Decimal,
        currency: String,
        category: Expense.Category,
        createdAt: Date,
        isRead: Bool = false,
        groupID: UUID? = nil,
        expenseID: UUID? = nil,
        isServerBacked: Bool = false
    ) {
        self.id             = id
        self.eventType      = eventType
        self.title          = title
        self.subtitle       = subtitle
        self.amount         = amount
        self.currency       = currency
        self.category       = category
        self.createdAt      = createdAt
        self.isRead         = isRead
        self.groupID        = groupID
        self.expenseID      = expenseID
        self.isServerBacked = isServerBacked
    }

    /// Cache entries written before this flag existed have no `isServerBacked` key.
    /// They decode as local; the next authoritative fetch re-flags the server rows.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(UUID.self, forKey: .id)
        eventType      = try c.decode(NotificationEventType.self, forKey: .eventType)
        title          = try c.decode(String.self, forKey: .title)
        subtitle       = try c.decode(String.self, forKey: .subtitle)
        amount         = try c.decode(Decimal.self, forKey: .amount)
        currency       = try c.decode(String.self, forKey: .currency)
        category       = try c.decode(Expense.Category.self, forKey: .category)
        createdAt      = try c.decode(Date.self, forKey: .createdAt)
        isRead         = try c.decode(Bool.self, forKey: .isRead)
        groupID        = try c.decodeIfPresent(UUID.self, forKey: .groupID)
        expenseID      = try c.decodeIfPresent(UUID.self, forKey: .expenseID)
        isServerBacked = try c.decodeIfPresent(Bool.self, forKey: .isServerBacked) ?? false
    }
}

// MARK: - Factory

extension NotificationItem {
    static func expense(
        _ expense: Expense,
        payerName: String,
        groupName: String,
        groupEmoji: String
    ) -> NotificationItem {
        // L-44: omit the emoji prefix entirely when groupEmoji is empty to prevent a
        // leading space in the subtitle (e.g. " Roommates · Paid by Alice").
        let emojiPrefix = groupEmoji.isEmpty ? "" : "\(groupEmoji) "
        return NotificationItem(
            id:        expense.id,
            eventType: .expenseAdded,
            title:     expense.title,
            subtitle:  "\(emojiPrefix)\(groupName) · Paid by \(payerName)",
            amount:    expense.amount,
            currency:  expense.currency,
            category:  expense.category,
            createdAt: expense.createdAt,
            groupID:   expense.groupID,
            expenseID: expense.id
        )
    }

    static func settlement(
        suggestion: SettlementSuggestion,
        groupName: String,
        groupEmoji: String
    ) -> NotificationItem {
        // M-28: derive a deterministic UUID from the settlement's stable attributes so
        // NotificationStore.merge can deduplicate settlement notifications across launches.
        // Swift's Hasher is not launch-stable, so we use a djb2-style fold over unicode scalars.
        let idSource = suggestion.fromUserID.uuidString
            + suggestion.toUserID.uuidString
            + suggestion.amount.description
            + suggestion.currency
        let hash = idSource.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 31) &+ UInt64($1.value) }
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 { bytes[i] = UInt8((hash >> (i * 8)) & 0xFF) }
        // Set UUID version 4 and variant bits so the result is a valid RFC-4122 UUID.
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let deterministicID = UUID(uuid: (
            bytes[0], bytes[1], bytes[2],  bytes[3],
            bytes[4], bytes[5], bytes[6],  bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
        return NotificationItem(
            id:        deterministicID,
            eventType: .settlementMade,
            title:     "\(suggestion.fromName) settled up",
            subtitle:  "\(groupEmoji) \(groupName) · Paid \(suggestion.toName)",
            amount:    suggestion.amount,
            currency:  suggestion.currency,
            // Settlements have no spending category; .other is the canonical placeholder.
            category:  .other,
            createdAt: Date()
        )
    }

    static func remote(
        id: UUID,
        eventType: NotificationEventType,
        title: String,
        subtitle: String,
        amount: Decimal,
        currency: String,
        category: Expense.Category,
        createdAt: Date,
        isRead: Bool,
        groupID: UUID?,
        expenseID: UUID?
    ) -> NotificationItem {
        NotificationItem(
            id: id,
            eventType: eventType,
            title: title,
            subtitle: subtitle,
            amount: amount,
            currency: currency,
            category: category,
            createdAt: createdAt,
            isRead: isRead,
            groupID: groupID,
            expenseID: expenseID,
            isServerBacked: true
        )
    }
}
