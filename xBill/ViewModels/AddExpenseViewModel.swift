//
//  AddExpenseViewModel.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import Observation

@Observable
@MainActor
final class AddExpenseViewModel {

    // MARK: - Form State

    var title: String = ""
    var amountText: String = ""
    var currency: String          // group base currency
    var expenseCurrency: String   // currency the expense was paid in
    var category: Expense.Category = .other
    var notes: String = ""
    var splitStrategy: SplitStrategy = .equal
    var splitInputs: [SplitInput] = []
    var payerID: UUID?

    // Multi-currency
    var convertedAmount: Decimal?     // amount in group currency (nil = same currency)
    var exchangeRate: Double?         // rate used
    var isFetchingRate: Bool = false

    var recurrence: Expense.Recurrence = .none

    var isLoading: Bool = false
    var isSaved: Bool = false
    var errorAlert: ErrorAlert?

    let group: BillGroup
    private let members: [User]
    private let expenseService = ExpenseService.shared

    // MARK: - Init

    init(group: BillGroup, members: [User], currentUserID: UUID) {
        self.group          = group
        self.members        = members
        self.currency       = group.currency
        self.expenseCurrency = group.currency
        self.payerID        = currentUserID
        self.splitInputs    = members.map {
            SplitInput(userID: $0.id, displayName: $0.displayName, avatarURL: $0.avatarURL)
        }
    }

    // MARK: - Computed

    var amount: Decimal {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")) ?? .zero
    }

    var isForeignCurrency: Bool { expenseCurrency != currency }

    /// The amount that will be recorded in the group's base currency.
    var finalAmount: Decimal {
        isForeignCurrency ? (convertedAmount ?? .zero) : amount
    }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
        && amount > .zero
        && payerID != nil
        && splitInputs.contains(where: \.isIncluded)
        && (!isForeignCurrency || convertedAmount != nil)
    }

    var splitValidationError: String? {
        guard splitStrategy == .exact else { return nil }
        return SplitCalculator.validateExact(total: finalAmount, inputs: splitInputs)
    }

    // MARK: - Split Recompute

    func recomputeSplits() {
        let total = finalAmount
        guard total > .zero else { return }
        switch splitStrategy {
        case .equal:
            SplitCalculator.splitEqually(total: total, inputs: &splitInputs)
        case .percentage:
            SplitCalculator.splitByPercentage(total: total, inputs: &splitInputs)
        case .shares:
            SplitCalculator.splitByShares(total: total, inputs: &splitInputs)
        case .exact:
            break
        }
    }

    func toggle(participantID: UUID) {
        guard let index = splitInputs.firstIndex(where: { $0.userID == participantID }) else { return }
        splitInputs[index].isIncluded.toggle()
        recomputeSplits()
    }

    // MARK: - Currency Conversion

    func updateConversion() async {
        guard isForeignCurrency, amount > .zero else {
            convertedAmount = nil
            exchangeRate    = nil
            recomputeSplits()
            return
        }
        isFetchingRate = true
        defer { isFetchingRate = false }
        do {
            let rate = try await ExchangeRateService.shared.rate(from: expenseCurrency, to: currency)
            exchangeRate    = rate
            convertedAmount = (amount * Decimal(rate)).rounded(scale: 2)
            recomputeSplits()
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }

    // MARK: - Save

    func save() async {
        guard canSave, let payerID else { return }

        // If foreign currency, need a valid conversion
        if isForeignCurrency && convertedAmount == nil {
            await updateConversion()
            guard convertedAmount != nil else { return }
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let nextOccurrence: Date? = recurrence != .none
                ? recurrence.nextDate(from: Date())
                : nil
            let expense = try await expenseService.createExpense(
                groupID:             group.id,
                title:               title.trimmingCharacters(in: .whitespaces),
                amount:              finalAmount,
                currency:            currency,
                payerID:             payerID,
                category:            category,
                notes:               notes.isEmpty ? nil : notes,
                splits:              splitInputs,
                originalAmount:      isForeignCurrency ? amount : nil,
                originalCurrency:    isForeignCurrency ? expenseCurrency : nil,
                recurrence:          recurrence,
                nextOccurrenceDate:  nextOccurrence
            )
            isSaved = true

            let payerName = members.first(where: { $0.id == payerID })?.displayName ?? "Someone"
            Task {
                await expenseService.notifyExpenseAdded(
                    expenseID:    expense.id,
                    groupID:      group.id,
                    payerID:      payerID,
                    payerName:    payerName,
                    expenseTitle: expense.title,
                    amount:       expense.amount,
                    currency:     expense.currency
                )
            }
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }
}

// MARK: - Decimal helper

private extension Decimal {
    func rounded(scale: Int) -> Decimal {
        var result = Decimal()
        var copy = self
        NSDecimalRound(&result, &copy, scale, .plain)
        return result
    }
}
