import Foundation
import UIKit
import Observation

@Observable
@MainActor
final class ReceiptViewModel {

    // MARK: - State

    var capturedImage:     UIImage?
    var scannedReceipt:    Receipt?
    var isScanning:        Bool    = false
    var error:             AppError?

    // Parsing metadata
    var confidence:        Double  = 0.0
    var validationWarning: String? = nil
    var parsingTier:       String  = ""   // "Apple Intelligence" or "Heuristic"

    /// Items with optional user assignments (for splitting by item)
    var items:   [ReceiptItem] = []
    var members: [User]        = []

    private let vision = VisionService.shared

    // MARK: - Computed

    var totalFromItems: Decimal {
        items.reduce(.zero) { $0 + $1.totalPrice }
    }

    var tax:        Decimal { scannedReceipt?.tax ?? .zero }
    var tip:        Decimal { scannedReceipt?.tip ?? .zero }
    var grandTotal: Decimal { totalFromItems + tax + tip }

    var confidenceLabel: String {
        switch confidence {
        case 0.90...: return "High confidence"
        case 0.75...: return "Good confidence"
        default:      return "Low confidence — please review"
        }
    }

    // MARK: - Scan

    func scan(image: UIImage) async {
        capturedImage     = image
        isScanning        = true
        error             = nil
        validationWarning = nil
        defer { isScanning = false }
        do {
            let result        = try await vision.scanReceipt(from: image)
            scannedReceipt    = result.receipt
            items             = result.receipt.items
            confidence        = result.confidence
            validationWarning = result.validationWarning
            parsingTier       = result.tier
        } catch {
            self.error = AppError.from(error)
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

    func assignAll(userIDs: [UUID], to itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].assignedUserIDs = userIDs
    }

    // MARK: - Per-User Total

    func total(for userID: UUID) -> Decimal {
        let itemShare = items
            .filter { $0.assignedUserIDs.contains(userID) }
            .reduce(Decimal.zero) { total, item in
                guard !item.assignedUserIDs.isEmpty else { return total }
                return total + item.totalPrice / Decimal(item.assignedUserIDs.count)
            }

        guard !members.isEmpty else { return itemShare }
        let sharedExtra = (tax + tip) / Decimal(members.count)
        return (itemShare + sharedExtra).rounded
    }

    // MARK: - Convert to SplitInputs

    func asSplitInputs() -> [SplitInput] {
        members.map { member in
            var input = SplitInput(
                userID:      member.id,
                displayName: member.displayName,
                avatarURL:   member.avatarURL
            )
            input.amount     = total(for: member.id)
            input.isIncluded = input.amount > .zero
            return input
        }
    }

    // MARK: - Edit

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
        items[index] = ReceiptItem(
            id:        items[index].id,
            name:      items[index].name,
            quantity:  quantity,
            unitPrice: items[index].unitPrice
        )
    }
}
