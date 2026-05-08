//
//  ReceiptViewModel.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import UIKit
import Observation

@Observable
@MainActor
final class ReceiptViewModel {

    // MARK: - State

    /// All pages captured from the document camera (or a single image from photo library).
    var capturedPages:     [UIImage] = []
    var scannedReceipt:    Receipt?
    var isScanning:        Bool     = false
    var errorAlert:        ErrorAlert?

    var confidence:        Double   = 0.0
    var validationWarning: String?  = nil
    var parsingTier:       String   = ""
    var suggestedCategory: Expense.Category? = nil

    var items:        [ReceiptItem] = []
    var members:      [User]        = []

    // Editable scan fields — populated after scan, user can correct before confirming
    var merchantName: String = ""
    var totalAmount:  String = ""
    var tipAmount:    String = ""

    /// First page image, used for display in the scan preview.
    var capturedImage: UIImage? { capturedPages.first }

    private let vision = VisionService.shared

    // MARK: - Computed

    var totalFromItems: Decimal {
        items.reduce(.zero) { $0 + $1.totalPrice }
    }

    var tax: Decimal { scannedReceipt?.tax ?? .zero }

    /// User-edited tip overrides the OCR-scanned value so corrections affect totals.
    var tip: Decimal { Decimal(string: tipAmount.replacingOccurrences(of: ",", with: ".")) ?? scannedReceipt?.tip ?? .zero }

    var grandTotal: Decimal { totalFromItems + tax + tip }

    var confidenceLabel: String {
        switch confidence {
        case 0.90...: return "High confidence"
        case 0.75...: return "Good confidence"
        default:      return "Low confidence — please review"
        }
    }

    /// True when members exist but at least one item has no one assigned.
    var hasUnassignedItems: Bool {
        !members.isEmpty && items.contains { $0.assignedUserIDs.isEmpty }
    }

    // MARK: - Scan

    /// Processes one or more captured pages (Gap 6: multi-page support).
    func scan(pages: [UIImage]) async {
        // Clear all state from any previous scan before starting the new one
        // so a failed scan never shows stale results alongside a new error.
        scannedReceipt    = nil
        items             = []
        merchantName      = ""
        totalAmount       = ""
        tipAmount         = ""
        validationWarning = nil
        suggestedCategory = nil
        confidence        = 0.0
        parsingTier       = ""
        errorAlert        = nil

        isScanning = true
        defer { isScanning = false }
        do {
            let result        = try await vision.scanMultiPage(from: pages)
            scannedReceipt    = result.receipt
            items             = result.receipt.items
            confidence        = result.confidence
            validationWarning = result.validationWarning
            parsingTier       = result.tier
            suggestedCategory = result.suggestedCategory
            merchantName      = result.receipt.merchant ?? ""
            if let tip   = result.receipt.tip   { tipAmount   = "\(tip)"   }
            if let total = result.receipt.total  { totalAmount = "\(total)" }
        } catch {
            self.errorAlert = ErrorAlert(title: "Scan Failed", message: error.localizedDescription)
        }
    }

    // MARK: - Item Assignment

    func assign(userID: UUID, to itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        if items[index].assignedUserIDs.contains(userID) {
            items[index].assignedUserIDs.removeAll { $0 == userID }
        } else {
            items[index].assignedUserIDs.append(userID)
        }
    }

    /// If all members are assigned → unassign all. Otherwise → assign all members.
    func toggleAssignAll(to itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        let allIDs      = members.map(\.id)
        let allAssigned = allIDs.allSatisfy { items[index].assignedUserIDs.contains($0) }
        items[index].assignedUserIDs = allAssigned ? [] : allIDs
    }

    // MARK: - Per-User Total
    // Tax + tip are split only among members who have ≥1 item assigned,
    // not across all group members.

    func total(for userID: UUID) -> Decimal {
        let itemShare = items
            .filter { $0.assignedUserIDs.contains(userID) }
            .reduce(Decimal.zero) { total, item in
                guard !item.assignedUserIDs.isEmpty else { return total }
                return total + item.totalPrice / Decimal(item.assignedUserIDs.count)
            }

        let participatingIDs = Set(items.flatMap(\.assignedUserIDs))
        guard participatingIDs.contains(userID), !participatingIDs.isEmpty else {
            return itemShare.rounded
        }
        let sharedExtra = (tax + tip) / Decimal(participatingIDs.count)
        return (itemShare + sharedExtra).rounded
    }

    // MARK: - Convert to SplitInputs

    func asSplitInputs() -> [SplitInput] {
        members.map { member in
            var input = SplitInput(userID: member.id, displayName: member.displayName,
                                   avatarURL: member.avatarURL)
            let memberTotal  = total(for: member.id)
            input.amount     = memberTotal
            // Include the member even at $0 so they appear in the split list;
            // mark them excluded so validations don't treat them as participants.
            input.isIncluded = memberTotal > .zero
            return input
        }
    }

    // MARK: - Manual Entry

    func startManually(members: [User] = []) {
        self.members      = members
        capturedPages     = []
        scannedReceipt    = Receipt(
            id: UUID(), expenseID: nil, imageURL: nil,
            merchant: nil, items: [], subtotal: nil,
            tax: nil, tip: nil, total: nil,
            currency: "USD", transactionDate: nil, scannedAt: Date()
        )
        items             = []
        merchantName      = ""
        totalAmount       = ""
        tipAmount         = ""
        validationWarning = nil
        suggestedCategory = nil
        // Reset scan metadata so manual-entry UI doesn't show stale scan badges
        confidence        = 0.0
        parsingTier       = ""
        errorAlert        = nil
        isScanning        = false
    }

    // MARK: - Edit

    func updateUnitPrice(itemID: UUID, unitPrice: Decimal) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        let existing = items[index]
        // Perform both mutations in a single assignment to avoid two @Observable UI updates.
        var updated = ReceiptItem(id: existing.id, name: existing.name,
                                  quantity: existing.quantity, unitPrice: unitPrice)
        updated.assignedUserIDs = existing.assignedUserIDs
        items[index] = updated
    }

    func updateItem(_ item: ReceiptItem) {
        items = items.replacing(item)
    }

    func removeItem(id: UUID) {
        items = items.removing(id: id)
    }

    func addItem(name: String, unitPrice: Decimal, quantity: Int = 1) {
        items.append(ReceiptItem(name: name, quantity: quantity, unitPrice: unitPrice))
    }

    func updateQuantity(itemID: UUID, quantity: Int) {
        guard quantity >= 1,
              let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        let existing = items[index]
        // Perform both mutations in a single assignment to avoid two @Observable UI updates.
        var updated = ReceiptItem(id: existing.id, name: existing.name,
                                  quantity: quantity, unitPrice: existing.unitPrice)
        updated.assignedUserIDs = existing.assignedUserIDs
        items[index] = updated
    }
}
