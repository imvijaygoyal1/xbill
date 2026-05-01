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

    init(
        id: UUID,
        eventType: NotificationEventType,
        title: String,
        subtitle: String,
        amount: Decimal,
        currency: String,
        category: Expense.Category,
        createdAt: Date,
        isRead: Bool = false
    ) {
        self.id        = id
        self.eventType = eventType
        self.title     = title
        self.subtitle  = subtitle
        self.amount    = amount
        self.currency  = currency
        self.category  = category
        self.createdAt = createdAt
        self.isRead    = isRead
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
        NotificationItem(
            id:        expense.id,
            eventType: .expenseAdded,
            title:     expense.title,
            subtitle:  "\(groupEmoji) \(groupName) · Paid by \(payerName)",
            amount:    expense.amount,
            currency:  expense.currency,
            category:  expense.category,
            createdAt: expense.createdAt
        )
    }

    static func settlement(
        suggestion: SettlementSuggestion,
        groupName: String,
        groupEmoji: String
    ) -> NotificationItem {
        NotificationItem(
            id:        suggestion.id,
            eventType: .settlementMade,
            title:     "\(suggestion.fromName) settled up",
            subtitle:  "\(groupEmoji) \(groupName) · Paid \(suggestion.toName)",
            amount:    suggestion.amount,
            currency:  suggestion.currency,
            category:  .other,
            createdAt: Date()
        )
    }
}
