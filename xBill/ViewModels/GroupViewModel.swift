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
    /// The payment this VM most recently recorded — carries the row's own `id` (not just its
    /// value) so `deletePayment` can tell whether the row it is deleting is the one that armed
    /// the duplicate-window below, as opposed to some other, older payment with the same
    /// from/to/amount. See `recordPayment` / `deletePayment` — IMP-4.
    @ObservationIgnored private var lastRecordedPayment: (id: UUID, from: UUID, to: UUID, amount: Decimal, at: Date)?
    /// Window in which an identical `recordPayment` call is treated as a duplicate of the one
    /// just recorded. Long enough to cover a user completing a Venmo/PayPal handoff and
    /// returning to answer "Did you complete this payment?" after already marking the same
    /// debt settled another way; short enough that a genuine repeat payment between the same
    /// two people is not silently dropped.
    private static let duplicatePaymentWindow: TimeInterval = 60
    /// A change this VM made to the ledger that a settlements fetch may not yet reflect,
    /// tagged with the fetch generation at which it was made.
    ///
    /// `generation` is the value of `settlementFetchGeneration` when the change was applied,
    /// i.e. how many settlement fetches had *started* by then. A fetch numbered `g` therefore
    /// started after this change iff `g > generation`, and such a fetch is authoritative over
    /// it — see `applyFetchedSettlements`.
    private enum PendingSettlementChange {
        /// A payment `recordPayment` committed, or one `deletePayment` put back after its
        /// delete reported an error. The second case does **not** assert the server still has
        /// the row — a failed delete may have committed anyway — only that this VM is showing
        /// it again; see `deletePayment`.
        case recorded(Settlement, generation: UInt64)
        /// A payment `deletePayment` removed locally. Keeps a fetch whose snapshot predates
        /// the delete from putting the row back — but only while the entry outranks that
        /// fetch. It is first written *before* the delete request, at which point the row is
        /// still on the server, so a `load()` issued in that window claims a higher generation
        /// and expires it; `deletePayment` closes that by tagging again after the commit and
        /// re-removing the row. This case alone does not make a deleted row stay deleted.
        case deleted(generation: UInt64)

        var generation: UInt64 {
            switch self {
            case .recorded(_, let generation), .deleted(let generation): return generation
            }
        }
    }

    /// Local ledger changes not yet known to be reflected by a fetch, keyed by settlement id.
    /// `applyFetchedSettlements` applies these over a fetch result and, crucially, **discards
    /// each one as soon as a fetch that started after it returns** — that expiry is what keeps
    /// the map bounded and stops any single entry from overriding the server forever. See that
    /// method for the two defects an unbounded version caused.
    @ObservationIgnored private var pendingSettlementChanges: [UUID: PendingSettlementChange] = [:]
    /// Count of settlement fetches started by this VM. Only ever compared, never persisted;
    /// monotonicity is the only property it needs. Mutated on the main actor exclusively.
    @ObservationIgnored private var settlementFetchGeneration: UInt64 = 0
    /// Generation of the newest settlements response that has actually been applied. Zero
    /// means none has. `applyFetchedSettlements` refuses anything at or below it, so a slower
    /// earlier fetch cannot overwrite a newer one's result. See I4 in that method's comment.
    @ObservationIgnored private var lastAppliedSettlementGeneration: UInt64 = 0
    /// Consecutive fetches that returned no settlements while this VM believed the server had
    /// some. Reset by any fetch that is applied. See the empty-response guard in
    /// `applyFetchedSettlements`.
    @ObservationIgnored private var consecutiveEmptySettlementFetches = 0
    /// How many consecutive empty settlement responses it takes before an empty fetch is
    /// believed rather than treated as a stale read. One empty response is refused (the
    /// observed PostgREST flake behind `applyFetchedExpenses`' guard); a second, from an
    /// independent request, is accepted so a genuinely emptied ledger cannot be pinned forever.
    private static let emptySettlementFetchesBeforeTrusted = 2
    private let logger = Logger(subsystem: "com.vijaygoyal.xbill", category: "GroupViewModel")
    private let groupService: any GroupDataProviding
    private let expenseService: any ExpenseDataProviding
    private let settlementService: any SettlementDataProviding
    private let currentUserIDProvider: @MainActor () -> UUID?
    /// R2: injection seam mirroring `currentUserIDProvider` so a test can force `load()` down
    /// its offline branch deterministically. `NetworkMonitor.shared.isConnected` is a real
    /// `NWPathMonitor`-backed singleton with a `private(set)` property — nothing in the test
    /// target could previously flip it, so the offline branch had zero coverage.
    private let isConnectedProvider: @MainActor () -> Bool

    init(
        group: BillGroup,
        groupService: any GroupDataProviding = GroupService.shared,
        expenseService: any ExpenseDataProviding = ExpenseService.shared,
        settlementService: any SettlementDataProviding = SettlementService.shared,
        currentUserIDProvider: @escaping @MainActor () -> UUID? = { AuthService.shared.currentUserID },
        isConnectedProvider: @escaping @MainActor () -> Bool = { NetworkMonitor.shared.isConnected }
    ) {
        self.groupService = groupService
        self.expenseService = expenseService
        self.settlementService = settlementService
        self.currentUserIDProvider = currentUserIDProvider
        self.isConnectedProvider = isConnectedProvider
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

    /// True when the settle-up suggestions currently on screen may be too high, because the
    /// last load could not confirm which of them were already paid.
    ///
    /// This is deliberately **not** the same condition as `GroupDetailView`'s empty-list error
    /// state. That state replaces an empty suggestions list with a retry prompt — there is
    /// nothing to show, so nothing is at risk of being wrong. This one is the opposite and more
    /// dangerous case: `settlementSuggestions` is non-empty, so there IS a list on screen, and
    /// it was computed with `settlements` possibly missing rows a fetch failure (R1) or a gap in
    /// offline caching (R2) could not surface — every unaccounted-for payment inflates a debt
    /// to its gross, pre-payment amount with a Record Payment button still showing. Requiring
    /// `settlementSuggestions.isEmpty` (as the empty-list predicate does) makes a warning here
    /// impossible in exactly the case it exists to catch — the residual finding this property
    /// fixes.
    ///
    /// `!isLoading && !isLoadingBalances` matches the empty-list predicate: a warning should not
    /// flash on top of suggestions that are mid-recompute from a load already in flight.
    var settlementsMayBeStale: Bool {
        !settlementSuggestions.isEmpty && balanceLoadFailed && !isLoading && !isLoadingBalances
    }

    /// True exactly when the Settle Up tab should show its full-list error/retry state —
    /// nothing safe to render, so it replaces the (empty) suggestions list. Extracted verbatim
    /// from what was a `GroupDetailView`-private computed property, unchanged, so a regression
    /// test can assert this rendering decision directly rather than only the `balanceLoadFailed`
    /// flag that feeds it and several other states besides. Deliberately requires
    /// `settlementSuggestions.isEmpty` — see `settlementsMayBeStale` for the non-empty case this
    /// one cannot and must not cover.
    var settleUpErrorStateShouldShow: Bool {
        (hasKnownNonEmptyExpenses || !expenses.isEmpty) &&
        settlementSuggestions.isEmpty &&
        balanceLoadFailed &&
        !isLoading &&
        !isLoadingBalances
    }

    /// True exactly when the Settle Up tab should show its loading/refresh overlay. Extracted
    /// verbatim from a `GroupDetailView`-private computed property, unchanged.
    var settleUpRefreshStateShouldShow: Bool {
        (hasKnownNonEmptyExpenses || !expenses.isEmpty) &&
        settlementSuggestions.isEmpty &&
        (isLoading || isLoadingBalances || (!hasLoadedBalances && !balanceLoadFailed))
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
            ("connected", isConnectedProvider()),
            ("expenses", expenses.count),
            ("cachedExpenses", CacheService.shared.loadExpenses(groupID: group.id).count),
            ("suggestions", settlementSuggestions.count),
            ("hasLoadedBalances", hasLoadedBalances),
            ("balanceLoadFailed", balanceLoadFailed),
            ("hasKnownNonEmpty", hasKnownNonEmptyExpenses)
        ])

        if isConnectedProvider() {
            do {
                // REV-04: cleared here, before the fetch. It used to be cleared at the top of
                // computeBalances, which runs *after* applyFetchedExpenses — so a stale-data
                // warning raised by the fetch was wiped before any view could read it.
                balanceLoadFailed = false
                let groupID = group.id
                let groupService = groupService
                let expenseService = expenseService
                let settlementService = settlementService
                // Claimed before the request goes out, so any local ledger change made from
                // here on is tagged with a higher generation than this fetch and survives it.
                let settlementsGeneration = beginSettlementsFetch()
                let (fetchedMembers, fetchedExpenses, fetchedSettlements) =
                    try await withTimeout(duration: .seconds(12)) {
                        async let membersTask     = groupService.fetchMembers(groupID: groupID, includeInactive: true)
                        async let expensesTask    = expenseService.fetchExpenses(groupID: groupID, limit: nil)
                        async let settlementsTask = settlementService.fetchSettlements(groupID: groupID)
                        return try await (membersTask, expensesTask, settlementsTask)
                    }
                members  = fetchedMembers
                applyFetchedSettlements(fetchedSettlements, fetchGeneration: settlementsGeneration)
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
                    ("connected", isConnectedProvider()),
                    ("error", AppDiagnostics.describe(error))
                ])
                guard !AppError.isSilent(error) else { return }
                // C1: the three fetches share one `try await` tuple, so a failure in ANY of
                // them lands here — including a settlements-only failure while members and
                // expenses succeeded. `settlements` then still holds whatever it held before
                // (empty on a first load), and `computeBalances()` below derives balances
                // from an unoffset ledger: every split counts as unpaid and Settle Up renders
                // the full, gross, pre-payment debt with a Record Payment button on each row.
                // A user could pay a debt they have already paid.
                //
                // `balanceLoadFailed` was cleared at the top of this branch (REV-04) and was
                // never restored here, so that gross figure was presented as authoritative
                // with no stale-data warning. Raise it for the same reason `HomeViewModel`
                // does on its settlements branch (IMP-2): the failure mode of a missing
                // settlements read is the largest possible wrong number, not a small one.
                balanceLoadFailed = true
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
            // R2: `CacheService` has no settlements persistence, so a view model that has never
            // loaded online — or was just created offline — always starts with `settlements ==
            // []`, indistinguishable from "no payments have ever been made". Without this guard
            // that renders every debt at its gross, pre-payment amount with `balanceLoadFailed`
            // still false — the same defect as the online settlements-fetch failure above, just
            // reached with no network error and no warning at all. Two cases must NOT raise it:
            // a genuinely empty group (nothing to be wrong about — `hasKnownNonEmptyExpenses` is
            // false), and a VM that already has `settlements` populated in memory from an
            // earlier successful online load in this session (going offline afterward does not
            // invalidate a ledger this VM already has).
            if hasKnownNonEmptyExpenses, settlements.isEmpty {
                balanceLoadFailed = true
            }
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

    /// Claims the next fetch generation. Call immediately before issuing a settlements fetch;
    /// the returned value identifies that fetch to `applyFetchedSettlements`.
    private func beginSettlementsFetch() -> UInt64 {
        settlementFetchGeneration += 1
        return settlementFetchGeneration
    }

    /// Applies a settlements fetch, overlaying the local changes this fetch cannot have seen.
    ///
    /// A plain `settlements = fetchedSettlements` is not safe: `recordPayment` and
    /// `deletePayment` do not wait on `isLoading`, so the server can capture its read before a
    /// local write commits, and a straight replace would drop that write off the balance.
    ///
    /// The overlay is bounded by **fetch generation**, and that bound is the whole point. Every
    /// entry in `pendingSettlementChanges` records how many fetches had started when it was
    /// made; this fetch started after any entry whose generation is lower, so for those entries
    /// the response is authoritative and the entry is discarded — whatever it says. An entry
    /// only survives while a fetch that could have seen it has yet to come back. Two earlier
    /// shapes lacked that expiry and both permanently pinned a row that the server did not have:
    ///
    /// - Round 2 kept *every* local row a fetch omitted (`settlements.filter { !fetchedIDs.contains($0.id) }`),
    ///   so another member's delete — absent from every later fetch — was re-added forever.
    ///   `REV-03` reproduced on money.
    /// - Round 3 bounded that to rows this VM recorded, but the map entry itself never expired.
    ///   A `deletePayment` whose server call committed and *then* failed to report success
    ///   re-pinned the row on its error path; every later fetch omitted it, so the pin held
    ///   forever and permanently credited a payment the ledger did not contain. A retry could
    ///   not clear it either — deleting an already-deleted row affects zero rows, which
    ///   `SupabaseWrite.requireAffected` correctly reports as a failure, landing back on the
    ///   same re-pin. Generation expiry ends that: the first fetch issued after the failed
    ///   delete discards the entry and the row goes with it.
    ///
    /// The same expiry closes the two-device case: a delete on another device is absent from
    /// every later fetch, and this VM has no entry to override it with.
    ///
    /// It does **not**, on its own, stop a fetch whose snapshot predates a successful delete
    /// from resurrecting the row — the `.deleted` entry outranks such a fetch only while the
    /// entry is younger than it, and the entry is first tagged *before* the delete request goes
    /// out. `deletePayment` closes that by tagging again once the write commits and re-removing
    /// the row if a fetch put it back in the meantime; see its success branch. Expiry alone
    /// cannot, because the resurrecting merge has already run by then.
    private func applyFetchedSettlements(_ fetchedSettlements: [Settlement], fetchGeneration: UInt64) {
        // I4: generation expiry above decides which *local* changes a response outranks. It says
        // nothing about which of two responses outranks the other, and two loads really can be
        // in flight at once: `deletePayment` takes no `!isLoading` guard and its `defer` clears
        // `isLoading` while an earlier `load()` is still awaiting its fetches, so the next
        // refresh sails past `load()`'s own guard. If load B (generation 2) returns first and
        // load A (generation 1) returns after it, A's older snapshot was applied wholesale on
        // top of B's — a payment recorded between the two fetches disappeared and the balance
        // reverted to gross until something triggered another fetch.
        //
        // Only a response strictly newer than the last one applied may be applied. Discarding a
        // stale response loses nothing: everything in it is, by construction, also in the newer
        // one, minus whatever the newer one has that it lacks.
        //
        // The counter advances here rather than at the end, so it also covers the one path
        // below that returns without writing `settlements` — the empty-response guard. That
        // guard's decision is "keep what we have and warn"; letting an older response through
        // afterwards would quietly overturn it with data that is older still.
        guard fetchGeneration > lastAppliedSettlementGeneration else {
            logger.warning("Discarding a settlements response from generation \(fetchGeneration, privacy: .public); generation \(self.lastAppliedSettlementGeneration, privacy: .public) has already been applied")
            return
        }
        lastAppliedSettlementGeneration = fetchGeneration

        // Rows recorded after this fetch started are not rows it failed to return, so they must
        // not make an empty response look suspicious.
        let expectedFromServer = settlements.filter { !isRecordedAfterFetch($0.id, generation: fetchGeneration) }
        if fetchedSettlements.isEmpty, !expectedFromServer.isEmpty {
            consecutiveEmptySettlementFetches += 1
            if consecutiveEmptySettlementFetches < Self.emptySettlementFetchesBeforeTrusted {
                // Same defence as `applyFetchedExpenses`: an empty reload for a group known to
                // have rows has actually been observed on this PostgREST surface, and accepting
                // it would silently show gross, pre-payment debt. Keep what we have and raise
                // the stale-data warning. Unlike the expenses guard this one is bounded — a
                // second independent empty response is believed, so a ledger that really was
                // emptied elsewhere cannot be pinned here indefinitely.
                balanceLoadFailed = true
                logger.warning("Keeping previous settlements because a reload returned none for a group with recorded payments")
                return
            }
            logger.warning("Accepting an empty settlement reload after \(Self.emptySettlementFetchesBeforeTrusted, privacy: .public) consecutive empty responses")
        }
        consecutiveEmptySettlementFetches = 0

        // Expire every entry this fetch is authoritative over.
        pendingSettlementChanges = pendingSettlementChanges.filter { $0.value.generation >= fetchGeneration }

        var merged = fetchedSettlements
        var pendingInserts: [Settlement] = []
        for (id, change) in pendingSettlementChanges {
            switch change {
            case .deleted:
                merged.removeAll { $0.id == id }
            case .recorded(let settlement, _):
                if !merged.contains(where: { $0.id == id }) { pendingInserts.append(settlement) }
            }
        }
        // The fetch is ordered newest-first, and a `.recorded` entry that survived the expiry
        // above was necessarily recorded after this fetch started — so it is newer than every
        // row the response contains, and belongs at the front. Balances are order-insensitive, but
        // the payment history list Tasks 6-8 add is not — appending would have made a
        // just-recorded payment jump from the top of the list to the bottom on the next load.
        settlements = pendingInserts.sorted { $0.createdAt > $1.createdAt } + merged
    }

    /// True when `id` names a payment recorded locally after fetch `generation` started — the
    /// one case where a fetch legitimately does not know about a row this VM is showing.
    private func isRecordedAfterFetch(_ id: UUID, generation fetchGeneration: UInt64) -> Bool {
        if case .recorded(_, let recordedAt) = pendingSettlementChanges[id] {
            return recordedAt >= fetchGeneration
        }
        return false
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
                    ("connected", isConnectedProvider()),
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
            applyDerivedBalances()
        } while shouldRecomputeBalances
    }

    /// Recomputes balances and suggestions from state already in memory. Pure and synchronous:
    /// no fetch, no `await`, no suspension point.
    ///
    /// Recording or deleting a payment changes the settlements ledger; it cannot change a
    /// single split. `splitsMap` is therefore already correct, and the round-trip
    /// `computeBalances()` makes is not merely wasted — it is the crash.
    ///
    /// `deletePayment` used to remove the row from `settlements` and then `await
    /// computeBalances()`. The `await` split one user action into two separately published
    /// mutations of the same `List`: the payment section lost a row immediately, and the
    /// settle-up section gained one only after the network returned. Both landed while the
    /// swipe-delete animation was still running, so `UICollectionView` was handed a batch
    /// update it could not reconcile against its own applied state and aborted with
    /// `NSInternalInconsistencyException`: "the number of items ... after the update (3) must
    /// be equal to the number ... before the update (2), plus or minus the number inserted (0)"
    /// — device crash 2026-08-01, `diagnostics/2026-08-01-settlements/crash3.log`.
    ///
    /// Calling this instead keeps both mutations in a single synchronous turn, so SwiftUI sees
    /// one coherent state change. `load()` still refreshes `splitsMap` from the network.
    private func applyDerivedBalances() {
        balances = SplitCalculator.netBalances(
            expenses: expenses, splits: splitsMap, settlements: settlements)
        settlementSuggestions = SplitCalculator.settlementSuggestions(
            expenses: expenses, splits: splitsMap, settlements: settlements,
            names: memberNames, currency: group.currency)
        hasLoadedBalances = true
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
        guard isConnectedProvider() else { return }
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

    /// Applies an expense that has ALREADY been saved by `update_expense_with_splits`.
    ///
    /// Deliberately performs no network call. This used to be `updateExpense`, which wrote the
    /// row a second time: a wasted round-trip that also put the client's stale `updated_at` back
    /// into the row, undoing the concurrency guard microseconds after it passed. See
    /// `ApplySavedExpenseTests`.
    func applySavedExpense(_ saved: Expense) async {
        guard let i = expenses.firstIndex(where: { $0.id == saved.id }) else { return }
        expenses[i] = saved
        await computeBalances()
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
    /// - The `contains` check before the insert below. It is not there because the merge in
    ///   `applyFetchedSettlements` could otherwise produce two entries for one id — it cannot,
    ///   the merge only adds a pending row the fetch did not already return. It is there for
    ///   the window *inside* this method's own `await`: `settlementService.recordSettlement`
    ///   can commit on the server before this call resumes, and a concurrent `load()` can
    ///   fetch, observe the committed row (this VM has not recorded it in
    ///   `pendingSettlementChanges` yet, so nothing stops the fetch from including it), and
    ///   finish its merge — all before this method's `await` returns. When it does return,
    ///   `settlements` already holds the row; inserting again unconditionally would duplicate it.
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
            // Tagged with the current generation, so only a fetch issued from here on can
            // retire it. A fetch already in flight cannot have seen this row and must not be
            // allowed to drop it.
            pendingSettlementChanges[saved.id] = .recorded(saved, generation: settlementFetchGeneration)
            if !settlements.contains(where: { $0.id == saved.id }) {
                settlements.insert(saved, at: 0)
            }
            lastRecordedPayment = (id: saved.id, from: fromUserID, to: toUserID, amount: amount, at: Date())
            applyDerivedBalances()

            let note = NotificationItem.settlement(
                suggestion: SettlementSuggestion(
                    fromUserID: fromUserID, fromName: memberNames[fromUserID] ?? "Someone",
                    toUserID: toUserID, toName: memberNames[toUserID] ?? "Someone",
                    amount: amount, currency: group.currency),
                groupName: group.name, groupEmoji: group.emoji)
            // I1: scoped to the account that recorded it, not the debtor. `NotificationStore`
            // keys are user-scoped, and this is a local Activity entry for what *this device's*
            // signed-in user just did. Before this branch only the debtor could settle, so
            // `fromUserID == recordedBy` always held and the distinction never showed; breaking
            // that invariant is the whole point of the settlements ledger. With `fromUserID`,
            // a creditor recording a payment filed the note under the debtor's key on the
            // recorder's own device — so the recorder saw no Activity row at all, and the
            // debtor would only see it if they ever signed in on that device.
            NotificationStore.shared.merge([note], userID: recordedBy)

            // PUSH-01: ungated. The recipient's own preference is applied by the Edge Function;
            // the person recording a payment does not decide whether the other party is told.
            await expenseService.notifySettlementRecorded(settlementID: saved.id)

            // A debt was just closed — the one moment in xBill worth asking for a review. Placed
            // at the end of the `do` block so it is unreachable from the duplicate-payment
            // early return and from every failure path: a prompt after a payment that did not
            // record is worse than no prompt.
            ReviewPromptService.shared.recordPositiveEvent()
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
    ///
    /// The local removal is recorded as a `.deleted` entry in `pendingSettlementChanges` rather
    /// than by clearing the id out of the map. A fetch already in flight holds a snapshot that
    /// still contains this row, and without the entry that fetch would put it straight back —
    /// harmless for balances today, but the delete affordance Tasks 6-8 add makes a resurrected
    /// row deletable, and deleting a row the server no longer has fails, which lands on the
    /// error path below.
    ///
    /// The entry is tagged **twice**, and both tags are load-bearing — they cover different
    /// fetches and neither substitutes for the other.
    ///
    /// Every other entry in the map is written after its change has committed, which is what
    /// makes "a fetch issued later is authoritative over it" true. This one is written *before*
    /// the request as well, because a fetch already in flight holds a snapshot that still
    /// contains the row and would otherwise merge it straight back; only the early tag stops
    /// that, and nothing written after the commit can, because that merge has already run.
    ///
    /// The early tag does not, however, satisfy the generation invariant: the row is still on
    /// the server when it is written, so a `load()` issued between the tag and the commit
    /// legitimately claims a higher generation and expires it. The success branch therefore
    /// tags again after the commit — restoring the invariant — and re-removes the row in case
    /// that `load()` already put it back.
    func deletePayment(_ settlement: Settlement) async {
        // The 2026-08-01 device crash landed here with no trace, because neither this method
        // nor `recordPayment` logged anything: the log's silence could not distinguish "never
        // reached" from "crashed midway". That is the same gap recorded after the notification
        // work — log the success path, not only failures.
        AppDiagnostics.log(.balance, "GroupViewModel.deletePayment.enter", [
            ("id", settlement.id.uuidString),
            ("amount", settlement.amount.description),
            ("settlements", settlements.count),
            ("suggestions", settlementSuggestions.count)
        ])
        isLoading = true
        defer { isLoading = false }
        settlements.removeAll { $0.id == settlement.id }
        pendingSettlementChanges[settlement.id] = .deleted(generation: settlementFetchGeneration)
        applyDerivedBalances()
        do {
            try await settlementService.deleteSettlement(id: settlement.id)
            // Re-assert the removal now that the delete has actually committed. Both halves are
            // needed and neither substitutes for the other:
            //   - The re-tag restores the generation invariant. The tag set before the request
            //     claims "a fetch issued after this observes it", which is not true until the
            //     write lands. A `load()` starting in between claims a higher generation and
            //     expires that first tag.
            //   - The re-removal handles the case where such a `load()` already finished: its
            //     merge put the row back in `settlements`, and expiry cannot undo a merge that
            //     has already run.
            let wasResurrected = settlements.contains { $0.id == settlement.id }
            settlements.removeAll { $0.id == settlement.id }
            pendingSettlementChanges[settlement.id] = .deleted(generation: settlementFetchGeneration)
            // Only when something actually changed — `computeBalances` refetches the split map,
            // and the common path here removes nothing because the optimistic removal still holds.
            if wasResurrected { applyDerivedBalances() }
            // Correcting a mistake — delete, then immediately re-record the same amount — must
            // not be swallowed by the IMP-4 duplicate window above. Keyed on the settlement's
            // own id, not its (from, to, amount) value: an *older* payment between the same two
            // people for the same amount must not clear a window armed seconds ago by a
            // different, newer payment.
            if lastRecordedPayment?.id == settlement.id {
                lastRecordedPayment = nil
            }
            AppDiagnostics.log(.balance, "GroupViewModel.deletePayment.committed", [
                ("id", settlement.id.uuidString),
                ("wasResurrected", wasResurrected),
                ("settlements", settlements.count),
                ("suggestions", settlementSuggestions.count)
            ])
        } catch {
            // Scoped rollback: re-insert only this settlement, and only if nothing else (a
            // concurrent load(), a retry) has already put it back.
            if !settlements.contains(where: { $0.id == settlement.id }) {
                settlements.append(settlement)
            }
            // Replaces the `.deleted` entry set above, which would otherwise keep hiding the
            // row from a fetch already in flight even though the delete did not take effect.
            // This says only "the row is back locally" — it does *not* assert the server still
            // has it. It cannot: an error here is equally consistent with the delete having
            // committed and the response having been lost. That ambiguity is why the entry
            // expires at the next fetch instead of persisting: whichever happened, the first
            // response issued after this point settles it.
            pendingSettlementChanges[settlement.id] = .recorded(settlement, generation: settlementFetchGeneration)
            applyDerivedBalances()
            AppDiagnostics.log(.balance, "GroupViewModel.deletePayment.catch", [
                ("id", settlement.id.uuidString),
                ("silent", AppError.isSilent(error)),
                ("settlements", settlements.count),
                ("error", AppDiagnostics.describe(error))
            ])
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
