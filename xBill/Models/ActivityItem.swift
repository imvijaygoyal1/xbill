//
//  ActivityItem.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation

struct ActivityItem: Identifiable, Sendable {
    let id: UUID
    let expenseTitle: String
    let amount: Decimal
    let currency: String
    let category: Expense.Category
    let payerName: String
    let groupName: String
    let groupEmoji: String
    let createdAt: Date
}
