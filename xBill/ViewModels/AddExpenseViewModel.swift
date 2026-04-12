import Foundation
import Observation

@Observable
@MainActor
final class AddExpenseViewModel {

    // MARK: - Form State

    var title: String = ""
    var amountText: String = ""
    var currency: String = "USD"
    var category: Expense.Category = .other
    var notes: String = ""
    var splitStrategy: SplitStrategy = .equal
    var splitInputs: [SplitInput] = []
    var payerID: UUID?

    var isLoading: Bool = false
    var isSaved: Bool = false
    var error: AppError?

    let group: BillGroup
    private let members: [User]
    private let expenseService = ExpenseService.shared

    // MARK: - Init

    init(group: BillGroup, members: [User], currentUserID: UUID) {
        self.group    = group
        self.members  = members
        self.currency = group.currency
        self.payerID  = currentUserID
        self.splitInputs = members.map {
            SplitInput(userID: $0.id, displayName: $0.displayName, avatarURL: $0.avatarURL)
        }
    }

    // MARK: - Computed

    var amount: Decimal {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")) ?? .zero
    }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
        && amount > .zero
        && payerID != nil
        && splitInputs.contains(where: \.isIncluded)
    }

    var splitValidationError: String? {
        guard splitStrategy == .exact else { return nil }
        return SplitCalculator.validateExact(total: amount, inputs: splitInputs)
    }

    // MARK: - Split Recompute

    func recomputeSplits() {
        guard amount > .zero else { return }
        switch splitStrategy {
        case .equal:
            SplitCalculator.splitEqually(total: amount, inputs: &splitInputs)
        case .percentage:
            SplitCalculator.splitByPercentage(total: amount, inputs: &splitInputs)
        case .exact:
            break
        }
    }

    func toggle(participantID: UUID) {
        guard let index = splitInputs.firstIndex(where: { $0.userID == participantID }) else { return }
        splitInputs[index].isIncluded.toggle()
        recomputeSplits()
    }

    // MARK: - Save

    func save() async {
        guard canSave, let payerID else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let expense = try await expenseService.createExpense(
                groupID:  group.id,
                title:    title.trimmingCharacters(in: .whitespaces),
                amount:   amount,
                currency: currency,
                payerID:  payerID,
                category: category,
                notes:    notes.isEmpty ? nil : notes,
                splits:   splitInputs
            )
            isSaved = true

            // Notify group members (fire-and-forget, errors silently ignored)
            let payerName = members.first(where: { $0.id == payerID })?.displayName ?? "Someone"
            Task {
                await expenseService.notifyExpenseAdded(
                    expenseID:     expense.id,
                    groupID:       group.id,
                    payerName:     payerName,
                    expenseTitle:  expense.title,
                    amount:        expense.amount,
                    currency:      expense.currency
                )
            }
        } catch {
            self.error = AppError.from(error)
        }
    }
}
