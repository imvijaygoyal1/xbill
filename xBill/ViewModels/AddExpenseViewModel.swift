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
    /// SPLIT-01: the split half of this form now lives in `SplitEditor`, shared with the edit
    /// sheet so the two cannot drift. These forward so this type's API is unchanged.
    let splitEditor = SplitEditor()

    var splitStrategy: SplitStrategy {
        get { splitEditor.strategy }
        set { splitEditor.strategy = newValue }
    }
    var splitInputs: [SplitInput] {
        get { splitEditor.inputs }
        set { splitEditor.inputs = newValue }
    }
    var payerID: UUID?

    // Multi-currency
    var convertedAmount: Decimal?     // amount in group currency (nil = same currency)
    var exchangeRate: Decimal?        // rate used (Decimal to avoid Double precision loss)
    var isFetchingRate: Bool = false

    var recurrence: Expense.Recurrence = .none

    var isLoading: Bool = false
    var isSaved: Bool = false
    var savedExpense: Expense?
    var errorAlert: ErrorAlert?

    let group: BillGroup
    private let members: [User]
    private let currentUserID: UUID
    private let expenseService = ExpenseService.shared

    // MARK: - Init

    init(group: BillGroup, members: [User], currentUserID: UUID) {
        self.group          = group
        self.members        = members
        self.currentUserID  = currentUserID
        self.currency       = group.currency
        self.expenseCurrency = group.currency
        self.payerID        = currentUserID
        self.splitInputs    = members.map {
            SplitInput(userID: $0.id, displayName: $0.displayName, avatarURL: $0.avatarURL)
        }
    }

    // MARK: - Computed

    var amount: Decimal {
        // Normalize comma decimals before Decimal(string:) because POSIX parsing can
        // partially parse "12,34" as 12 instead of failing.
        if amountText.contains(",") {
            let normalized = amountText.replacingOccurrences(of: ",", with: ".")
            if let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) {
                return value
            }
        }

        // Try POSIX locale for standard decimal input.
        if let value = Decimal(string: amountText, locale: Locale(identifier: "en_US_POSIX")) {
            return value
        }
        return .zero
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
        && splitValidationError == nil
    }

    /// Passes `finalAmount` explicitly: the editor's stored total only refreshes on recompute,
    /// and `canSave` is read on every keystroke.
    var splitValidationError: String? { splitEditor.validationError(for: finalAmount) }

    // MARK: - Split Recompute

    func recomputeSplits() {
        // The editor is the single source of truth for the split; this is where the form's
        // (possibly currency-converted) total is handed to it. `total`'s `didSet` recomputes.
        splitEditor.total = finalAmount
        splitEditor.recompute()
    }

    // MARK: - Participant edits
    //
    // CRASH-01. Every mutation of a participant row resolves the row **by id**, and a
    // participant that is no longer present is a no-op rather than a trap.
    //
    // The view previously edited rows through `ForEach($vm.splitInputs)` element bindings, which
    // are backed by an **array index**. UIKit reads those bindings from `Switch.updateUIView`
    // during a deferred update pass — after the body that produced them has returned — and an
    // index that no longer resolves calls `Array._checkSubscript`, which traps. That shipped in
    // 1.0 (1) and crashed on a real device. `firstIndex(where:)` + `guard` cannot trap, so
    // routing every edit through these makes the whole class of failure unrepresentable rather
    // than merely unlikely.

    func input(for participantID: UUID) -> SplitInput? {
        splitEditor.input(for: participantID)
    }

    func toggle(participantID: UUID) {
        splitEditor.total = finalAmount
        splitEditor.toggle(participantID: participantID)
    }

    func setAmount(_ amount: Decimal, participantID: UUID) {
        splitEditor.setAmount(amount, participantID: participantID)
    }

    func adjustShares(by delta: Int, participantID: UUID) {
        splitEditor.total = finalAmount
        splitEditor.adjustShares(by: delta, participantID: participantID)
    }

    // MARK: - Currency Conversion

    /// Tracks the in-flight conversion task so stale responses from earlier
    /// currency changes cannot overwrite the result from the most recent change.
    private var conversionTask: Task<Void, Never>?

    func updateConversion() async {
        guard isForeignCurrency, amount > .zero else {
            convertedAmount = nil
            exchangeRate    = nil
            recomputeSplits()
            return
        }

        // Cancel any previous in-flight rate fetch so that a slow response
        // from an earlier currency selection cannot overwrite a newer one.
        conversionTask?.cancel()
        conversionTask = Task {
            isFetchingRate = true
            defer { isFetchingRate = false }
            do {
                let rate = try await ExchangeRateService.shared.rate(from: expenseCurrency, to: currency)
                // If this task was cancelled while awaiting the network call,
                // discard the stale result rather than writing it to state.
                guard !Task.isCancelled else { return }
                exchangeRate    = rate
                convertedAmount = (amount * rate).rounded(scale: 2)
                recomputeSplits()
            } catch {
                guard !Task.isCancelled else { return }
                guard !AppError.isSilent(error) else { return }
                self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
            }
        }
        await conversionTask?.value
    }

    // MARK: - Save

    func save() async {
        // Fast-path guard before the async suspension point.
        guard canSave, let payerID else { return }

        // If foreign currency, resolve conversion first
        if isForeignCurrency && convertedAmount == nil {
            await updateConversion()
        }

        // Re-validate canSave after async suspension; payerID local already bound above.
        guard canSave else { return }

        // Capture finalAmount after conversion is settled and before any further await,
        // so a concurrent amountText edit cannot alter the value mid-save.
        let capturedAmount = finalAmount

        isLoading = true
        defer { isLoading = false }

        do {
            let nextOccurrence: Date? = recurrence != .none
                ? recurrence.nextDate(from: Date())
                : nil
            let expense = try await expenseService.createExpense(
                groupID:             group.id,
                title:               title.trimmingCharacters(in: .whitespaces),
                amount:              capturedAmount,
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
            savedExpense = expense
            isSaved = true

            // Await the notification inline — isSaved drives sheet dismissal, not isLoading.
            if CacheService.defaults.bool(forKey: NotificationService.expensePreferenceKey) {
                await expenseService.notifyExpenseAdded(
                    expenseID: expense.id
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
        NSDecimalRound(&result, &copy, scale, .bankers)
        return result
    }
}
