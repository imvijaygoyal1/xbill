//
//  PreviewData.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation

enum PreviewData {
    static let currentUser = User(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        email: "maya@example.com",
        displayName: "Maya Patel",
        avatarURL: nil,
        createdAt: .now
    )

    static let friends: [User] = [
        currentUser,
        User(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, email: "jordan@example.com", displayName: "Jordan Lee", avatarURL: nil, createdAt: .now),
        User(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, email: "sam@example.com", displayName: "Sam Rivera", avatarURL: nil, createdAt: .now),
        User(id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!, email: "alex@example.com", displayName: "Alex Chen", avatarURL: nil, createdAt: .now)
    ]

    static let groups: [BillGroup] = [
        BillGroup(id: UUID(), name: "Weekend Trip", emoji: "✈️", createdBy: currentUser.id, isArchived: false, currency: "USD", createdAt: .now),
        BillGroup(id: UUID(), name: "Roommates", emoji: "🏠", createdBy: currentUser.id, isArchived: false, currency: "USD", createdAt: .now),
        BillGroup(id: UUID(), name: "Dinner Club", emoji: "🍕", createdBy: currentUser.id, isArchived: false, currency: "USD", createdAt: .now)
    ]

    static let expenses: [Expense] = [
        Expense(
            id: UUID(),
            groupID: groups[0].id,
            title: "Hotel",
            amount: 420,
            currency: "USD",
            payerID: currentUser.id,
            category: .accommodation,
            notes: nil,
            receiptURL: nil,
            originalAmount: nil,
            originalCurrency: nil,
            recurrence: .none,
            nextOccurrenceDate: nil,
            createdAt: .now
        ),
        Expense(
            id: UUID(),
            groupID: groups[0].id,
            title: "Tacos",
            amount: 86.40,
            currency: "USD",
            payerID: friends[1].id,
            category: .food,
            notes: nil,
            receiptURL: nil,
            originalAmount: nil,
            originalCurrency: nil,
            recurrence: .none,
            nextOccurrenceDate: nil,
            createdAt: .now
        )
    ]
}
