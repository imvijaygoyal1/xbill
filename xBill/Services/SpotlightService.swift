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

    // MARK: - Expense index cleanup

    /// Removes all previously indexed expense items. Expense titles contain financial data
    /// (amounts, categories) which would be visible in Spotlight from the lock screen,
    /// bypassing App Lock. Groups are indexed instead — they contain only name and emoji.
    static func removeAllExpenses() {
        CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: [expenseDomain]
        ) { _ in }
    }
}
