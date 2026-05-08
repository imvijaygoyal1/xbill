//
//  SpotlightService.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import CoreSpotlight
import UniformTypeIdentifiers
import Foundation
import os

// MARK: - SpotlightService

/// Indexes and removes app content from CoreSpotlight.
/// Errors are logged via os_log (not silently discarded) so issues surface during development.
enum SpotlightService {

    private static let groupDomain   = "com.vijaygoyal.xbill.group"
    private static let expenseDomain = "com.vijaygoyal.xbill.expense"
    private static let logger = Logger(subsystem: "com.vijaygoyal.xbill", category: "Spotlight")

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
        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error {
                logger.error("Spotlight index failed: \(error.localizedDescription)")
            }
        }
    }

    static func removeGroup(id: UUID) {
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: ["group:\(id.uuidString)"]
        ) { error in
            if let error {
                logger.error("Spotlight delete group failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Expense index cleanup

    /// Removes all previously indexed expense items. Expense titles contain financial data
    /// (amounts, categories) which would be visible in Spotlight from the lock screen,
    /// bypassing App Lock. Groups are indexed instead — they contain only name and emoji.
    static func removeAllExpenses() {
        CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: [expenseDomain]
        ) { error in
            if let error {
                logger.error("Spotlight removeAllExpenses failed: \(error.localizedDescription)")
            }
        }
    }
}
