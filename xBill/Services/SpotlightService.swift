//
//  SpotlightService.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import CoreSpotlight
import UniformTypeIdentifiers
import Foundation

// MARK: - SpotlightService

/// Indexes and removes app content from CoreSpotlight.
/// All methods are fire-and-forget; errors are silently ignored.
enum SpotlightService {

    private static let groupDomain   = "com.vijaygoyal.xbill.group"
    private static let expenseDomain = "com.vijaygoyal.xbill.expense"

    // MARK: - Groups

    static func indexGroups(_ groups: [BillGroup]) {
        let items = groups.map { group -> CSSearchableItem in
            let attr = CSSearchableItemAttributeSet(contentType: .content)
            attr.title = "\(group.emoji) \(group.name)"
            attr.contentDescription = "Group · \(group.currency)"
            attr.keywords = [group.name, group.emoji, group.currency, "group", "xbill"]
            let item = CSSearchableItem(
                uniqueIdentifier: "group:\(group.id.uuidString)",
                domainIdentifier: groupDomain,
                attributeSet: attr
            )
            item.expirationDate = .distantFuture
            return item
        }
        CSSearchableIndex.default().indexSearchableItems(items) { _ in }
    }

    static func removeGroup(id: UUID) {
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: ["group:\(id.uuidString)"]
        ) { _ in }
    }

    // MARK: - Expenses

    static func indexExpenses(_ expenses: [Expense], groupName: String, groupEmoji: String) {
        let items = expenses.map { expense -> CSSearchableItem in
            let attr = CSSearchableItemAttributeSet(contentType: .content)
            attr.title = expense.title
            attr.contentDescription = "\(expense.category.displayName) · \(groupEmoji) \(groupName)"
            attr.keywords = [expense.title, expense.category.displayName, groupName, "expense", "xbill"]
            let item = CSSearchableItem(
                uniqueIdentifier: "expense:\(expense.id.uuidString)",
                domainIdentifier: expenseDomain,
                attributeSet: attr
            )
            item.expirationDate = .distantFuture
            return item
        }
        CSSearchableIndex.default().indexSearchableItems(items) { _ in }
    }

    static func removeExpense(id: UUID) {
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: ["expense:\(id.uuidString)"]
        ) { _ in }
    }
}
