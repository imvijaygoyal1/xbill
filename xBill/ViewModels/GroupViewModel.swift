//
//  GroupViewModel.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class GroupViewModel {

    // MARK: - State

    var group: BillGroup
    var members: [User] = []
    var expenses: [Expense] = []
    var balances: [UUID: Decimal] = [:]
    var settlementSuggestions: [SettlementSuggestion] = []
    var settlements: [Settlement] = []
    var isLoading: Bool = false
    var isLoadingBalances: Bool = false
    var hasLoadedBalances: Bool = false
    var balanceLoadFailed: Bool = false
    var hasKnownNonEmptyExpenses: Bool = false
    var errorAlert: ErrorAlert?

    private var splitsMap: [UUID: [Split]] = [:]
    @ObservationIgnored private var locallyCreatedExpenses: [UUID: Expense] = [:]
    @ObservationIgnored private var isComputingBalances = false
    @ObservationIgnored private var shouldRecomputeBalances = false
    /// The last payment this VM successfully recorded, so a second call for the exact same
    /// (from, to, amount) shortly afterward is recognised as a duplicate rather than a new
    /// payment. See `recordPayment` — IMP-4.
    @ObservationIgnored private var lastRecordedPayment: (from: UUID, to: UUID, amount: Decimal, at: Date)?
    /// Window in which an identical `recordPayment` call is treated as a duplicate of the one
    /// just recorded. Long enough to cover a user completing a Venmo/PayPal handoff and
    /// returning to answer "Did you complete this payment?" after already marking the same
    /// debt settled another way; short enough that a genuine repeat payment between the same
    /// two people is not silently dropped.
    private static let duplicatePaymentWindow: TimeInterval = 60
    private let logger = Logger(subsystem: "com.vijaygoyal.xbill", category: "GroupViewModel")
    private let groupService: any GroupDataProviding
    private let expenseService: any ExpenseDataProviding
    private let settlementService: any SettlementDataProviding
    private let currentUserIDProvider: @MainActor () -> UUID?

    init(
        group: BillGroup,
        groupService: any GroupDataProviding = GroupService.shared,
        expenseService: any ExpenseDataProviding = ExpenseService.shared,
        settlementService: any SettlementDataProviding = SettlementService.shared,
        currentUserIDProvider: @escaping @MainActor () -> UUID? = { AuthService.shared.currentUserID }
    ) {
        self.groupService = groupService
        self.expenseService = expenseService
        self.settlementService = settlementService
        self.currentUserIDProvider = currentUserIDProvider
        self.group = group
        let cachedMembers = CacheService.shared.loadMembers(groupID: group.id)
        let cachedExpenses = CacheService.shared.loadExpenses(groupID: group.id)
        self.members = cachedMembers
        self.expenses = cachedExpenses
        self.hasKnownNonEmptyExpenses = !cachedExpenses.isEmpty || CacheService.shared.hasKnownNonEmptyExpenses(groupID: group.id)
    }

    // MARK: - Computed

    var memberNames: [UUID: String] {
        Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.displayName) })
    }

    var sortedExpenses: [Expense] {
        expenses.sorted { $0.createdAt > $1.createdAt }
    }

    var activeMembers: [User] {
        members.filter(\.isActive)
    }

    var canChangeCurrency: Bool {
        expenses.isEmpty
    }

    func balance(for userID: UUID) -> Decimal {
        balances[userID] ?? .zero
    }

    // MARK: - Load

    func load(showError: Bool = true) async {
        guard !isLoading else {
            AppDiagnostics.log(.balance, "GroupViewModel.load.skipped", [
                ("group", group.name),
                ("reason", "already loading")
            ])
            return
        }
        isLoading = true
        defer { isLoading = false }

        AppDiagnostics.log(.balance, "GroupViewModel.load.enter", [
            ("group", group.name),
            ("groupID", group.id.uuidString),
            ("showError", showError),
            ("connected", NetworkMonitor.shared.isConnected),
            ("expenses", expenses.count),
            ("cachedExpenses", CacheService.shared.loadExpenses(groupID: group.id).count),
            ("suggestions", settlementSuggestions.count),
            ("hasLoadedBalances", hasLoadedBalances),
            ("balanceLoadFailed", balanceLoadFailed),
            ("hasKnownNonEmpty", hasKnownNonEmptyExpenses)
        ])

        if NetworkMonitor.shared.isConnected {
            do {
                // REV-04: cleared here, before the fetch. It used to be cleared at the top of
                // computeBalances, which runs *after* applyFetchedExpenses — so a stale-data
                // warning raised by the fetch was wiped before any view could read it.
                balanceLoadFailed = false
                let groupID = group.id
                let groupService = groupService
                let expenseService = expenseService
                let settlementService = settlementService
                let (fetchedMembers, fetchedExpenses, fetchedSettlements) =
                    try await withTimeout(duration: .seconds(12)) {
                        async let membersTask     = groupService.fetchMembers(groupID: groupID, includeInactive: true)
                        async let expensesTask    = expenseService.fetchExpenses(groupID: groupID, limit: nil)
                        async let settlementsTask = settlementService.fetchSettlements(groupID: groupID)
                        return try await (membersTask, expensesTask, settlementsTask)
                    }
                members  = fetchedMembers
                applyFetchedSettlements(fetchedSettlements)
                applyFetchedExpenses(fetchedExpenses)
                hasKnownNonEmptyExpenses = hasKnownNonEmptyExpenses || !expenses.isEmpty
                CacheService.shared.saveMembers(fetchedMembers, groupID: group.id)
                CacheService.shared.saveExpenses(expenses, groupID: group.id)
                await computeBalances()
                AppDiagnostics.log(.balance, "GroupViewModel.load.success", [
                    ("group", group.name),
                    ("expenses", expenses.count),
                    ("suggestions", settlementSuggestions.count),
                    ("hasLoadedBalances", hasLoadedBalances),
                    ("balanceLoadFailed", balanceLoadFailed)
                ])
            } catch {
                AppDiagnostics.log(.balance, "GroupViewModel.load.catch", [
                    ("group", group.name),
                    ("showError", showError),
                    ("silent", AppError.isSilent(error)),
                    ("connected", NetworkMonitor.shared.isConnected),
                    ("error", AppDiagnostics.describe(error))
                ])
                guard !AppError.isSilent(error) else { return }
                // Unconditionally restore from cache on any network error — a partial
                // in-flight fetch may have written one array but not the other.
                let cachedMembers  = CacheService.shared.loadMembers(groupID: group.id)
                let cachedExpenses = CacheService.shared.loadExpenses(groupID: group.id)
                if !cachedMembers.isEmpty  { members  = cachedMembers }
                if !cachedExpenses.isEmpty { expenses = cachedExpenses }
                hasKnownNonEmptyExpenses = hasKnownNonEmptyExpenses || !cachedExpenses.isEmpty || CacheService.shared.hasKnownNonEmptyExpenses(groupID: group.id)
                if showError {
                    self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
                }
                await computeBalances()
            }
        } else {
            members  = CacheService.shared.loadMembers(groupID: group.id)
            expenses = CacheService.shared.loadExpenses(groupID: group.id)
            hasKnownNonEmptyExpenses = hasKnownNonEmptyExpenses || !expenses.isEmpty || CacheService.shared.hasKnownNonEmptyExpenses(groupID: group.id)
            await computeBalances()
        }
    }

    func refresh(showError: Bool = true) async { await load(showError: showError) }

    func recordCreatedExpense(_ expense: Expense) {
        locallyCreatedExpenses[expense.id] = expense
        if !expenses.contains(where: { $0.id == expense.id }) {
            expenses.append(expense)
        }
    }

    private func applyFetchedExpenses(_ fetchedExpenses: [Expense]) {
        if fetchedExpenses.isEmpty {
            let cachedExpenses = CacheService.shared.loadExpenses(groupID: group.id)
            if !expenses.isEmpty {
                hasKnownNonEmptyExpenses = true
                balanceLoadFailed = true
                logger.warning("Keeping previous expenses because reload returned an empty expense list for a non-empty group")
                return
            }
            if !cachedExpenses.isEmpty {
                hasKnownNonEmptyExpenses = true
                balanceLoadFailed = true
                logger.warning("Restoring cached expenses because reload returned an empty expense list")
                expenses = cachedExpenses
                return
            }
            if hasKnownNonEmptyExpenses || CacheService.shared.hasKnownNonEmptyExpenses(groupID: group.id) {
                hasKnownNonEmptyExpenses = true
                balanceLoadFailed = true
                logger.warning("Ignoring empty expense reload for a group previously known to have expenses")
                return
            }
        }

        var mergedExpenses = fetchedExpenses
        for expense in locallyCreatedExpenses.values where !mergedExpenses.contains(where: { $0.id == expense.id }) {
            mergedExpenses.append(expense)
        }
        for expense in fetchedExpenses {
            locallyCreatedExpenses.removeValue(forKey: expense.id)
        }
        expenses = mergedExpenses
        hasKnownNonEmptyExpenses = hasKnownNonEmptyExpenses || !mergedExpenses.isEmpty
    }

    /// Merges a fetch with whatever `recordPayment` may have inserted while the fetch was in
    /// flight, instead of replacing outright (IMP-1, round 2).
    ///
    /// A plain `settlements = fetchedSettlements` is safe only if nothing else can write
    /// `settlements` between the request going out and the response coming back — untrue here,
    /// since `recordPayment` no longer waits on `isLoading`. If the server captured its read
    /// before that insert committed, a replace would silently drop the just-recorded payment
    /// off the balance; if it captured its read after, a replace is harmless but a same-id
    /// `recordPayment` insert racing the assignment could still double up without the dedupe
    /// this merge makes load-bearing. Same shape as `applyFetchedExpenses` /
    /// `locallyCreatedExpenses`: trust the fetch, keep only what it does not yet know about.
    private func applyFetchedSettlements(_ fetchedSettlements: [Settlement]) {
        let fetchedIDs = Set(fetchedSettlements.map(\.id))
        let notYetVisibleToServer = settlements.filter { !fetchedIDs.contains($0.id) }
        settlements = notYetVisibleToServer + fetchedSettlements
    }

    // MARK: - Balances

    private func computeBalances() async {
        if isComputingBalances {
            shouldRecomputeBalances = true
            return
        }
        isComputingBalances = true
        isLoadingBalances = true
        defer { isComputingBalances = false }
        defer { isLoadingBalances = false }

        repeat {
            shouldRecomputeBalances = false
            do {
                let currentExpenses = expenses
                let expenseService = expenseService
                let fetchedSplitsMap = try await withTimeout(duration: .seconds(12)) {
                    try await SplitCalculator.fetchSplitsMap(for: currentExpenses, using: expenseService)
                }
                splitsMap = fetchedSplitsMap
            } catch {
                AppDiagnostics.log(.balance, "GroupViewModel.computeBalances.catch", [
                    ("group", group.name),
                    ("expenses", expenses.count),
                    ("splitsMap", splitsMap.count),
                    ("connected", NetworkMonitor.shared.isConnected),
                    ("error", AppDiagnostics.describe(error))
                ])
                // REV-05: `continue` rather than `return`. In a repeat/while this re-checks
                // the loop condition, so a recompute requested while this one was in flight
                // is still honoured. `return` dropped it, which is the exact failure the
                // coalescing was added to prevent.
                guard !expenses.isEmpty else { continue }
                guard !splitsMap.isEmpty else {
                    balanceLoadFailed = true
                    logger.error("Split loading failed with no previous split map: \(error.localizedDescription, privacy: .public)")
                    continue
                }
                balanceLoadFailed = true
                logger.warning("Keeping previous split map because split loading failed: \(error.localizedDescription, privacy: .public)")
            }
            balances = SplitCalculator.netBalances(
                expenses: expenses, splits: splitsMap, settlements: settlements)
            settlementSuggestions = SplitCalculator.settlementSuggestions(
                expenses: expenses, splits: splitsMap, settlements: settlements,
                names: memberNames, currency: group.currency)
            hasLoadedBalances = true
        } while shouldRecomputeBalances
    }

    // MARK: - Members

    func addMember(userId: UUID) async {
        do {
            try await groupService.addMember(groupId: group.id, userId: userId)
            await load()
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }

    func removeMember(userID: UUID) async {
        do {
            try await groupService.removeMember(groupId: group.id, userId: userID)
            await load()
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }

    func updateGroupDetails(name: String, emoji: String, currency: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorAlert = ErrorAlert(title: "Missing Group Name", message: "Enter a group name before saving.")
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            var updated = group
            updated.name = trimmedName
            updated.emoji = emoji
            if currency != group.currency {
                guard canChangeCurrency else {
                    throw AppError.validationFailed("Currency cannot be changed after expenses have been added to this group.")
                }
                updated.currency = currency
            }
            group = try await groupService.updateGroup(updated)
            var cached = CacheService.shared.loadGroups()
            if let index = cached.firstIndex(where: { $0.id == group.id }) {
                cached[index] = group
                CacheService.shared.saveGroups(cached)
            }
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }

    // MARK: - Archive

    func archiveGroup() async {
        isLoading = true
        defer { isLoading = false }
        do {
            var updated = group
            updated.isArchived = true
            group = try await groupService.updateGroup(updated)
            // Remove from active-groups cache
            var active = CacheService.shared.loadGroups()
            active.removeAll { $0.id == group.id }
            CacheService.shared.saveGroups(active)
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }

    func unarchiveGroup() async {
        isLoading = true
        defer { isLoading = false }
        do {
            var updated = group
            updated.isArchived = false
            group = try await groupService.updateGroup(updated)
            var cached = CacheService.shared.loadGroups()
            if !cached.contains(where: { $0.id == group.id }) {
                cached.append(group)
                CacheService.shared.saveGroups(cached)
            }
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }

    // MARK: - Recurring Instances

    /// Creates new expense instances for any recurring expenses that are due, then advances
    /// the template's `next_occurrence_date`.
    ///
    /// Acts on every member's due templates, not just the caller's — `M-08` removed the
    /// payer filter so a group does not stall when one member does not open the app. The
    /// backend RPC claims each occurrence atomically, so concurrent callers are safe.
    func createDueRecurringInstances() async {
        guard NetworkMonitor.shared.isConnected else { return }
        do {
            let dueExpenses = try await expenseService.fetchDueRecurringExpenses(groupID: group.id)
            guard !dueExpenses.isEmpty else { return }

            for expense in dueExpenses {
                guard expense.recurrence != .none,
                      let nextDate = expense.nextOccurrenceDate else { continue }

                guard let newNextDate = expense.recurrence.nextDate(from: nextDate) else { continue }

                do {
                    _ = try await expenseService.createRecurringInstance(
                        templateID: expense.id,
                        expectedNextOccurrence: nextDate,
                        newNextOccurrence: newNextDate
                    )
                } catch {
                    Logger(subsystem: "com.vijaygoyal.xbill", category: "Recurring")
                        .fault("Failed to create recurring instance for expense \(expense.id): \(error)")
                }
            }

            await load(showError: false)
        } catch {
            guard !AppError.isSilent(error) else { return }
            // Recurring maintenance is opportunistic and should not block the group screen.
            // A later refresh will retry it without presenting a misleading payment/load error.
            AppDiagnostics.log(.balance, "GroupViewModel.createDueRecurringInstances.catch", [
                ("group", group.name),
                ("error", AppDiagnostics.describe(error))
            ])
            logger.warning("Recurring expense maintenance skipped: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Settle Up

    func deleteExpense(_ expense: Expense) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await expenseService.deleteExpense(id: expense.id)
            expenses.removeAll { $0.id == expense.id }
            splitsMap.removeValue(forKey: expense.id)
            // REV-03: applyFetchedExpenses re-merges anything still in this map that a fetch
            // does not return, and only clears an entry when the fetch *does* return it. A
            // deleted expense would therefore come back on every later load.
            locallyCreatedExpenses.removeValue(forKey: expense.id)
            await computeBalances()
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }

    func updateExpense(_ updated: Expense) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let saved = try await expenseService.updateExpense(updated)
            if let i = expenses.firstIndex(where: { $0.id == saved.id }) {
                expenses[i] = saved
            }
            await computeBalances()
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }

    /// Records a payment. Either party may do this; the database enforces it.
    ///
    /// Round 2 correction: this used to `guard !isLoading` before doing any work, on the theory
    /// that it would serialise against a `load()` already in flight. That was wrong in a way
    /// that made things worse, not safer — `load()` can hold `isLoading` for up to ~24s (three
    /// parallel fetches plus `computeBalances`, each under a 12s timeout), and a return from a
    /// payment app is exactly when `GroupDetailView.onChange(of: scenePhase)` kicks off a
    /// `refresh()`. A user tapping "Mark as Settled" into that window had the guard silently
    /// return — no write, no error, and (since the caller only shows an error alert, and gates
    /// its success haptic on `errorAlert == nil`) a **success haptic for a payment that was
    /// never recorded**. Worse, the handoff alert that is often the caller here is one-shot —
    /// its `isPresented` setter clears the prompt state — so there was no second chance. A
    /// user-initiated write must never be silently dropped to protect a read; see
    /// `applyFetchedSettlements` for how `load()` now makes room for this to interleave safely
    /// instead.
    ///
    /// Two things still protect the ledger from a duplicate write, in addition to whatever RLS
    /// enforces server-side:
    /// - Dedupe-on-insert by id, now load-bearing: `applyFetchedSettlements` keeps this VM's
    ///   local settlements across a `load()`'s replace, so a `load()` whose fetch happened to
    ///   observe this exact row (started after the insert committed, resolved after this method
    ///   returns) merges it back in under the *same* id — this `contains` check is what stops
    ///   that merge from producing two entries for one payment.
    /// - `lastRecordedPayment` (IMP-4) catches the *sequential* double-record case: two
    ///   different UI affordances (the settle-up confirmation and the post-handoff "did you
    ///   pay?" alert) can each independently call this for the same debt, one fully finishing
    ///   before the other starts.
    func recordPayment(from fromUserID: UUID, to toUserID: UUID, amount: Decimal) async {
        guard let recordedBy = currentUserIDProvider() else {
            errorAlert = ErrorAlert(title: "Not Signed In", message: "Sign in to record a payment.")
            return
        }
        if let last = lastRecordedPayment,
           last.from == fromUserID, last.to == toUserID, last.amount == amount,
           Date().timeIntervalSince(last.at) < Self.duplicatePaymentWindow {
            // Same payment as the one this VM just recorded, seconds ago — almost certainly
            // the same debt confirmed twice through two different UI paths, not a second real
            // payment. Recording it again would double-credit the debtor.
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let saved = try await settlementService.recordSettlement(
                groupID: group.id, fromUserID: fromUserID, toUserID: toUserID,
                amount: amount, currency: group.currency, recordedBy: recordedBy)
            if !settlements.contains(where: { $0.id == saved.id }) {
                settlements.insert(saved, at: 0)
            }
            lastRecordedPayment = (fromUserID, toUserID, amount, Date())
            await computeBalances()

            let note = NotificationItem.settlement(
                suggestion: SettlementSuggestion(
                    id: saved.id, fromUserID: fromUserID, fromName: memberNames[fromUserID] ?? "Someone",
                    toUserID: toUserID, toName: memberNames[toUserID] ?? "Someone",
                    amount: amount, currency: group.currency),
                groupName: group.name, groupEmoji: group.emoji)
            NotificationStore.shared.merge([note], userID: fromUserID)

            if CacheService.defaults.bool(forKey: NotificationService.settlementPreferenceKey) {
                await expenseService.notifySettlementRecorded(
                    settlementID: saved.id, groupID: group.id,
                    toUserID: toUserID, amount: amount, currency: group.currency)
            }
        } catch {
            guard !AppError.isSilent(error) else { return }
            errorAlert = ErrorAlert(title: "Payment Not Recorded", message: error.localizedDescription)
        }
    }

    /// Removes a payment. RLS permits this only for the account that recorded it.
    ///
    /// Round 2 correction: the rollback on a failed delete used to restore a whole `settlements`
    /// snapshot captured before the optimistic removal. That reverts more than the failed
    /// delete — any `recordPayment` insert that lands while the delete is in flight is wiped
    /// out along with it, even though it has nothing to do with this delete and its write
    /// already committed. This project has hit that exact class of bug twice before
    /// (`NOTIF-06`, `REV-06`), both times fixed the same way: scope the rollback to only the
    /// row this operation touched.
    func deletePayment(_ settlement: Settlement) async {
        isLoading = true
        defer { isLoading = false }
        settlements.removeAll { $0.id == settlement.id }
        await computeBalances()
        do {
            try await settlementService.deleteSettlement(id: settlement.id)
            // Correcting a mistake — delete, then immediately re-record the same amount — must
            // not be swallowed by the IMP-4 duplicate window above. Only clear it when the
            // deleted row is the one that armed it; an unrelated older payment being deleted
            // should not reopen the window for a payment recorded seconds ago.
            if let last = lastRecordedPayment,
               last.from == settlement.fromUserID, last.to == settlement.toUserID, last.amount == settlement.amount {
                lastRecordedPayment = nil
            }
        } catch {
            // Scoped rollback: re-insert only this settlement, and only if nothing else (a
            // concurrent load(), a retry) has already put it back.
            if !settlements.contains(where: { $0.id == settlement.id }) {
                settlements.append(settlement)
            }
            await computeBalances()
            guard !AppError.isSilent(error) else { return }
            errorAlert = ErrorAlert(title: "Payment Not Removed", message: error.localizedDescription)
        }
    }
}

internal func withTimeout<T: Sendable>(
    duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: duration)
            throw AppError.serverError("The request timed out. Check your connection and try again.")
        }

        guard let result = try await group.next() else {
            throw AppError.serverError("The request timed out. Check your connection and try again.")
        }
        group.cancelAll()
        return result
    }
}
