//
//  GroupDetailView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct GroupDetailView: View {
    // Owned in @State so the ViewModel survives parent body re-evaluations (e.g. App Lock
    // toggling on Venmo/return). Constructing it inline in the navigationDestination closure
    // rebuilt a fresh VM on every re-render, wiping loaded balances and never reloading —
    // the root cause of the perpetual "Refreshing balances…" after returning from Venmo.
    @State private var vm: GroupViewModel
    let currentUserID: UUID
    var onGroupStatusChanged: (() async -> Void)?
    @State private var showAddExpense = false
    @State private var showInvite = false
    @State private var showInviteLink = false
    @State private var showGroupSettings = false
    @State private var showStats = false
    @State private var showArchiveConfirm = false
    @State private var showUnarchiveConfirm = false
    @State private var expenseToDelete: Expense?
    @State private var paymentToRecord: SettlementSuggestion?
    @State private var shareItem: ExportShareItem?
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var filterCategory: Expense.Category? = nil
    @State private var paymentHandoffAlert: ErrorAlert?
    /// A payment app was opened for this suggestion and we are waiting to ask whether it
    /// completed. View state, not model state — a handoff has no meaning once this screen
    /// is gone.
    private struct PendingHandoff: Equatable {
        let suggestion: SettlementSuggestion
        let providerName: String
    }
    /// The handoff is held by exactly one of `.pending`/`.asking`, or neither (`.none`) —
    /// an invariant two independent optionals could not enforce and both shipped
    /// device-only handoff bugs were violations of it.
    private enum HandoffState: Equatable {
        case none
        /// Armed; waiting for a safe moment to present (e.g. App Lock still up, or the
        /// AppLockView dismissal transition still animating).
        case pending(PendingHandoff)
        /// The alert is, or should be, on screen.
        case asking(PendingHandoff)

        var askingPayload: PendingHandoff? {
            if case .asking(let payload) = self { return payload }
            return nil
        }

        /// Case label only — no `fromName`/`toName`/`amount`/`currency`. Used for diagnostic
        /// logging, which is DEBUG-only but should still never write a financial record to an
        /// on-device log for what a Bool previously covered.
        var caseLabel: String {
            switch self {
            case .none: return "none"
            case .pending: return "pending"
            case .asking: return "asking"
            }
        }
    }
    @State private var handoff: HandoffState = .none
    /// When `handoff` last transitioned into `.asking`. Used by `presentHandoffPromptIfReady()`
    /// to detect a wedged `.asking` — one whose alert presentation was dropped by SwiftUI —
    /// without tearing down an alert that is genuinely still on screen. `nil` whenever
    /// `handoff` is `.none` or `.pending`.
    @State private var askingSince: Date?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    init(group: BillGroup, currentUserID: UUID, onGroupStatusChanged: (() async -> Void)? = nil) {
        _vm = State(initialValue: GroupViewModel(group: group))
        self.currentUserID = currentUserID
        self.onGroupStatusChanged = onGroupStatusChanged
    }

    private var filteredExpenses: [Expense] {
        var result = vm.sortedExpenses
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter { exp in
                exp.title.lowercased().contains(q) ||
                exp.category.displayName.lowercased().contains(q) ||
                (exp.notes?.lowercased().contains(q) == true)
            }
        }
        if let cat = filterCategory {
            result = result.filter { $0.category == cat }
        }
        return result
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            decoratedContent

            // Keep the primary action visible offline, then explain why it cannot continue.
            if selectedTab == 0 {
                FABButton { openAddExpense() }
                    .accessibilityLabel(NetworkMonitor.shared.isConnected ? "Add Expense" : "Add Expense unavailable offline")
                    .padding(.bottom, AppSpacing.floatingActionBottomPadding)
                    .padding(.trailing, AppSpacing.md)
            }
        }
        .searchable(text: $searchText, prompt: "Search expenses")
    }

    // Splitting the modifier chain into intermediate `some View` properties keeps each
    // chain small enough for the type checker — a single mega-chain here previously hit
    // "unable to type-check this expression in reasonable time".
    private var baseContent: some View {
        Group {
            if vm.isLoading && vm.expenses.isEmpty {
                LoadingOverlay(message: "Loading group…")
            } else {
                content
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(AppColors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(Color.brandPrimary)
        .safeAreaInset(edge: .top) {
            if !NetworkMonitor.shared.isConnected { OfflineBanner() }
        }
    }

    private var lifecycleContent: some View {
        baseContent
            .task {
                AppDiagnostics.log(.lifecycle, "GroupDetailView.task.begin", [("group", vm.group.name)])
                // Payment-app handoffs can interrupt the first load. The group and balance
                // surfaces expose retryable state; do not show a generic alert for a transient
                // lifecycle/network failure while the user is returning to this screen.
                await vm.load(showError: false)
                await vm.createDueRecurringInstances()
                AppDiagnostics.log(.lifecycle, "GroupDetailView.task.end", [("group", vm.group.name)])
            }
            .onChange(of: scenePhase) { oldPhase, phase in
                let fields: [(String, Any)] = [
                    ("group", vm.group.name),
                    ("from", String(describing: oldPhase)),
                    ("to", String(describing: phase)),
                    ("connected", NetworkMonitor.shared.isConnected),
                    ("expenses", vm.expenses.count),
                    ("suggestions", vm.settlementSuggestions.count),
                    ("isLoading", vm.isLoading),
                    ("isLoadingBalances", vm.isLoadingBalances),
                    ("hasLoadedBalances", vm.hasLoadedBalances),
                    ("balanceLoadFailed", vm.balanceLoadFailed),
                    ("handoff", handoff.caseLabel),
                    ("isLocked", AppLockService.shared.isLocked)
                ]
                AppDiagnostics.log(.lifecycle, "GroupDetailView.scenePhase", fields)
                guard phase == .active else { return }
                // Payment providers return through different mechanisms: Venmo uses a custom
                // scheme while PayPal may return through Safari. Refresh on every active
                // transition so neither handoff depends on SwiftUI recreating this view.
                Task { await vm.refresh(showError: false) }
                presentHandoffPromptIfReady()
            }
            .onChange(of: AppLockService.shared.isLocked) { _, locked in
                // App Lock is engaged on backgrounding, so returning from a payment app
                // lands here still locked. Presenting now would render the dialog behind
                // the lock overlay; defer until unlock.
                if !locked { presentHandoffPromptIfReady() }
            }
            .refreshable { await vm.refresh() }
            .onChange(of: selectedTab) { _, _ in
                searchText = ""
                filterCategory = nil
            }
    }

    private var decoratedContent: some View {
        lifecycleContent
            .sheet(isPresented: $showAddExpense) {
                AddExpenseView(group: vm.group, members: vm.activeMembers, currentUserID: currentUserID) { savedExpense in
                    vm.recordCreatedExpense(savedExpense)
                }
            }
            .sheet(isPresented: $showGroupSettings) {
                GroupSettingsView(vm: vm, currentUserID: currentUserID) {
                    await onGroupStatusChanged?()
                }
            }
            .sheet(isPresented: $showInvite) {
                InviteMembersView(group: vm.group) {
                    await vm.load()
                    await onGroupStatusChanged?()
                }
            }
            .sheet(isPresented: $showInviteLink) {
                GroupInviteView(group: vm.group, currentUserID: currentUserID)
            }
            .sheet(item: $shareItem) { item in
                ShareSheetView(url: item.url)
                    .ignoresSafeArea()
            }
            .confirmationDialog(
                "Archive \"\(vm.group.name)\"?",
                isPresented: $showArchiveConfirm,
                titleVisibility: .visible
            ) {
                Button("Archive Group", role: .destructive) {
                    Task {
                        await vm.archiveGroup()
                        await onGroupStatusChanged?()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if vm.settlementSuggestions.isEmpty {
                    Text("The group will be hidden from your active list. You can unarchive it later from the Groups tab.")
                } else {
                    Text("This group has \(vm.settlementSuggestions.count) unsettled balance\(vm.settlementSuggestions.count == 1 ? "" : "s"). It will be hidden from your active list — you can unarchive it later from the Groups tab.")
                }
            }
            .confirmationDialog(
                "Unarchive \"\(vm.group.name)\"?",
                isPresented: $showUnarchiveConfirm,
                titleVisibility: .visible
            ) {
                Button("Unarchive Group") {
                    Task {
                        await vm.unarchiveGroup()
                        await onGroupStatusChanged?()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The group will be moved back to your active list.")
            }
            .confirmationDialog(
                "Delete Expense?",
                isPresented: Binding(
                    get: { expenseToDelete != nil },
                    set: { if !$0 { expenseToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    guard let expense = expenseToDelete else { return }
                    Task { await vm.deleteExpense(expense) }
                    expenseToDelete = nil
                }
                Button("Cancel", role: .cancel) { expenseToDelete = nil }
            } message: {
                Text("This will remove the expense and all its splits. This cannot be undone.")
            }
            .sheet(item: $paymentToRecord) { suggestion in
                RecordPaymentSheet(suggestion: suggestion, currency: vm.group.currency) { amount in
                    Task {
                        await vm.recordPayment(
                            from: suggestion.fromUserID, to: suggestion.toUserID, amount: amount)
                    }
                }
            }
            // An alert, not a confirmationDialog: this is a binary question, and a
            // .cancel-role button inside a confirmationDialog does not reliably render with
            // its own title — "Not yet" was missing on device while "Mark as Settled" showed.
            // An alert guarantees both titled buttons appear.
            //
            // Uses the `presenting:` overload so the payload is handed to the action
            // closures directly instead of being re-read from `@State` after the binding's
            // setter has already fired. SwiftUI does not contractually guarantee the alert
            // action runs before `isPresented`'s setter — re-reading `handoff` from inside
            // the action risked reading it after the setter had already reset it to `.none`.
            .alert(
                "Did you complete this payment?",
                isPresented: Binding(
                    get: { handoff.askingPayload != nil },
                    set: { if !$0 { handoff = .none; askingSince = nil } }
                ),
                presenting: handoff.askingPayload
            ) { prompt in
                // No body needed: the binding's setter above already clears `handoff` to
                // `.none`, so "cleared after one answer" is structural for both buttons.
                Button("Not yet", role: .cancel) { }
                Button("Mark as Settled") {
                    // Opens the amount sheet rather than recording the full suggested amount
                    // directly — xBill cannot confirm what actually went through in the
                    // payment app, so the user states the amount themselves.
                    paymentToRecord = prompt.suggestion
                }
            } message: { prompt in
                Text("xBill can't confirm payments made in \(prompt.providerName). Only mark this settled if the payment went through.")
            }
            .navigationDestination(isPresented: $showStats) {
                GroupStatsView(
                    expenses: vm.expenses,
                    members:  vm.members,
                    currency: vm.group.currency
                )
            }
            .alert(item: $paymentHandoffAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .errorAlert(item: $vm.errorAlert)
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            XBillPageHeader(
                title: vm.group.name,
                subtitle: "\(vm.group.currency) group",
                showsBackButton: true,
                backAction: { dismiss() },
                trailing: { groupMenu }
            )

            groupSummaryHeader

            // Segmented picker
            XBillSegmentedControl(
                options: [(0, "Expenses"), (1, "Balances"), (2, "Settle Up")],
                selection: $selectedTab
            )
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(AppColors.surface)

            AppColors.border.frame(height: 0.5)

            // Category filter strip (expenses tab only)
            if selectedTab == 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: XBillSpacing.xs) {
                        ExpenseFilterChip(label: "All", isSelected: filterCategory == nil) {
                            filterCategory = nil
                        }
                        ForEach(Expense.Category.allCases, id: \.self) { cat in
                            ExpenseFilterChip(
                                label: cat.displayName,
                                category: cat,
                                isSelected: filterCategory == cat
                            ) {
                                filterCategory = filterCategory == cat ? nil : cat
                            }
                        }
                    }
                    .padding(.horizontal, XBillSpacing.base)
                    .padding(.vertical, XBillSpacing.xs)
                }
                .background(AppColors.surface)

                AppColors.border.frame(height: 0.5)
            }

            // Tab content
            switch selectedTab {
            case 0: expensesTab
            case 1:
                if vm.isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    balancesTab
                }
            default:
                if vm.isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    settleUpTabEmbedded
                }
            }
        }
        .background(AppColors.background)
    }

    private var groupSummaryHeader: some View {
        HStack(spacing: AppSpacing.md) {
            XBillAvatarPlaceholder(name: vm.group.emoji, size: 56)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.sm) {
                    XBillAvatarStack(users: vm.activeMembers, maxVisible: 4, size: 28)
                    Text("\(vm.activeMembers.count) active member\(vm.activeMembers.count == 1 ? "" : "s")")
                        .font(.appCaption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            Spacer()
            XBillPillButton(title: "Manage", icon: "slider.horizontal.3", style: .secondary) {
                showGroupSettings = true
            }
            .accessibilityIdentifier("xBill.group.manageButton")
        }
        .padding(AppSpacing.md)
        .background(AppColors.background)
    }

    // MARK: - Expenses Tab

    private var expensesTab: some View {
        Group {
            if shouldShowExpenseRefreshState {
                LoadingOverlay(message: "Refreshing expenses…")
            } else if vm.sortedExpenses.isEmpty {
                EmptyStateView(
                    icon: "receipt.fill",
                    title: "No Expenses",
                    message: "Add the first expense to this group.",
                    actionLabel: "Add Expense",
                    action: { openAddExpense() }
                )
            } else if filteredExpenses.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No Results",
                    message: !searchText.isEmpty
                        ? "No expenses match your search."
                        : filterCategory != nil
                            ? "No expenses in this category."
                            : "No expenses found."
                )
            } else {
                List {
                    ForEach(filteredExpenses) { expense in
                        NavigationLink {
                            ExpenseDetailView(
                                expense: expense,
                                members: vm.members,
                                currency: vm.group.currency,
                                groupName: vm.group.name,
                                currentUserID: currentUserID,
                                onUpdated: { updated in Task { await vm.updateExpense(updated) } },
                                onDeleted: { Task { await vm.deleteExpense(expense) } }
                            )
                        } label: {
                            ExpenseRowView(expense: expense, members: vm.members, showAmountBadge: true)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(expense.title) expense, \(expense.amount.formatted(currencyCode: expense.currency))")
                        .accessibilityIdentifier("xBill.expenseRow.\(expense.title)")
                        .listRowBackground(Color.bgCard)
                    }
                    .onDelete { offsets in
                        // Show confirmation before deleting; actual delete fires from the dialog.
                        expenseToDelete = offsets.map({ filteredExpenses[$0] }).first
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .listRowSeparatorTint(Color.separator)
            }
        }
    }

    // MARK: - Balances Tab

    private var balancesTab: some View {
        List {
            ForEach(vm.members) { member in
                let balance = vm.balance(for: member.id)
                HStack(spacing: XBillSpacing.md) {
                    AvatarView(name: member.displayName, url: member.avatarURL, size: XBillIcon.avatarSm)
                    Text(member.displayName)
                        .font(.xbillBodyMedium)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    AmountBadge(
                        amount: abs(balance),
                        direction: balance > .zero ? .positive : balance < .zero ? .negative : .settled,
                        currency: vm.group.currency
                    )
                }
                .listRowBackground(Color.bgCard)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listRowSeparatorTint(Color.separator)
    }

    // MARK: - Settle Up Tab (embedded)

    private var settleUpTabEmbedded: some View {
        List {
            if shouldShowBalanceErrorState {
                EmptyStateView(
                    icon: "exclamationmark.triangle.fill",
                    title: "Couldn’t Refresh Balances",
                    message: "The expenses are still here, but xBill couldn’t reload the split details. Check your connection and try again.",
                    actionLabel: "Retry",
                    action: { Task { await vm.refresh() } }
                )
                .listRowBackground(Color.bgCard)
                .listRowSeparator(.hidden)
            } else if shouldShowBalanceRefreshState {
                LoadingOverlay(message: "Refreshing balances…")
                    .listRowBackground(Color.bgCard)
                    .listRowSeparator(.hidden)
            } else if vm.settlementSuggestions.isEmpty {
                EmptyStateView(
                    icon: "checkmark.circle.fill",
                    title: "All Settled Up!",
                    message: "No outstanding balances in this group."
                )
                .listRowBackground(Color.bgCard)
                .listRowSeparator(.hidden)
            } else {
                ForEach(vm.settlementSuggestions) { suggestion in
                    settlementRow(suggestion)
                        .listRowBackground(Color.bgCard)
                }
            }

            PaymentHistorySection(
                settlements: vm.settlements,
                memberNames: vm.memberNames,
                currency: vm.group.currency,
                currentUserID: currentUserID,
                onDelete: { settlement in Task { await vm.deletePayment(settlement) } })
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listRowSeparatorTint(Color.separator)
    }

    private var shouldShowBalanceRefreshState: Bool {
        (vm.hasKnownNonEmptyExpenses || !vm.expenses.isEmpty) &&
        vm.settlementSuggestions.isEmpty &&
        (vm.isLoading || vm.isLoadingBalances || (!vm.hasLoadedBalances && !vm.balanceLoadFailed))
    }

    private var shouldShowBalanceErrorState: Bool {
        (vm.hasKnownNonEmptyExpenses || !vm.expenses.isEmpty) &&
        vm.settlementSuggestions.isEmpty &&
        vm.balanceLoadFailed &&
        !vm.isLoading &&
        !vm.isLoadingBalances
    }

    private var shouldShowExpenseRefreshState: Bool {
        vm.expenses.isEmpty &&
        vm.hasKnownNonEmptyExpenses &&
        (vm.isLoading || vm.balanceLoadFailed)
    }

    private func settlementRow(_ suggestion: SettlementSuggestion) -> some View {
        let isParty = currentUserID == suggestion.fromUserID || currentUserID == suggestion.toUserID
        return VStack(spacing: XBillSpacing.md) {
            HStack(spacing: XBillSpacing.md) {
                AvatarView(name: suggestion.fromName, size: XBillIcon.avatarSm)
                Image(systemName: "arrow.right")
                    .foregroundStyle(Color.brandAccent)
                AvatarView(name: suggestion.toName, size: XBillIcon.avatarSm)
                Spacer()
                Text(suggestion.amount.formatted(currencyCode: suggestion.currency))
                    .font(.xbillLargeAmount)
                    .foregroundStyle(Color.textPrimary)
            }
            if isParty {
                XBillButton(title: "Record Payment", style: .primary) {
                    paymentToRecord = suggestion
                }
                .accessibilityIdentifier("xBill.settleUp.recordPaymentButton.\(suggestion.id.uuidString)")
            }
            if currentUserID == suggestion.fromUserID,
               let recipient = vm.members.first(where: { $0.id == suggestion.toUserID }) {
                let venmoHandle  = PaymentHandleValidator.normalized(recipient.venmoHandle, for: .venmo)
                let paypalHandle = PaymentHandleValidator.normalized(recipient.paypalHandle, for: .paypal)

                if venmoHandle == nil && paypalHandle == nil {
                    // Previously this rendered nothing at all, so the absence of a payment
                    // button looked like a bug rather than missing recipient data.
                    Text("Ask \(suggestion.toName) to add a payment handle in their profile.")
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("xBill.settleUp.noPaymentHandle.\(suggestion.id.uuidString)")
                } else {
                    HStack(spacing: AppSpacing.sm) {
                        if let handle = venmoHandle,
                           let venmoURL = PaymentLinkService.shared.paymentLink(for: suggestion, recipient: recipient, method: .venmo) {
                            Button {
                                openPaymentURL(venmoURL, providerName: "Venmo", suggestion: suggestion)
                            } label: {
                                Label("Venmo · @\(handle)", systemImage: "link")
                                    .font(.appCaptionMedium)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("xBill.settleUp.venmoButton.\(suggestion.id.uuidString)")
                        }
                        if let handle = paypalHandle,
                           let paypalURL = PaymentLinkService.shared.paymentLink(for: suggestion, recipient: recipient, method: .paypal) {
                            Button {
                                openPaymentURL(paypalURL, providerName: "PayPal", suggestion: suggestion)
                            } label: {
                                Label("PayPal · @\(handle)", systemImage: "link")
                                    .font(.appCaptionMedium)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("xBill.settleUp.paypalButton.\(suggestion.id.uuidString)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, XBillSpacing.sm)
        .opacity(isParty ? 1 : 0.55)
        .accessibilityIdentifier("xBill.settleUp.suggestionRow.\(suggestion.id.uuidString)")
    }

    private func openPaymentURL(_ url: URL, providerName: String, suggestion: SettlementSuggestion) {
        AppDiagnostics.log(.payment, "GroupDetailView.openPaymentURL.request", [
            ("provider", providerName),
            ("scheme", url.scheme ?? "nil"),
            ("host", url.host() ?? "nil"),
            ("url", url.absoluteString),
            ("group", vm.group.name)
        ])
        openURL(url) { accepted in
            AppDiagnostics.log(.payment, "GroupDetailView.openPaymentURL.result", [
                ("provider", providerName),
                ("accepted", accepted)
            ])
            guard accepted else {
                paymentHandoffAlert = ErrorAlert(
                    title: "\(providerName) Not Available",
                    message: "Install \(providerName) or use another payment method, then mark the settlement when it is complete."
                )
                return
            }
            // A fresh tap always supersedes whatever `handoff` currently holds — including a
            // stale `.asking`. If an alert were genuinely on screen it is modal, so the user
            // could not have reached this button to trigger a second handoff; the only
            // `.asking` this can ever replace is one a dropped presentation left wedged with
            // no alert visible. Previously this bailed out here, which meant a single dropped
            // presentation permanently disarmed every later handoff on this screen — every
            // subsequent Venmo/PayPal tap opened the payment app and armed nothing. A new
            // handoff must never be silently dropped.
            askingSince = nil
            // Only arm the prompt when the payment app actually opened.
            handoff = .pending(PendingHandoff(suggestion: suggestion, providerName: providerName))
        }
    }

    private func presentHandoffPromptIfReady() {
        // `.asking` is not self-recovering: `.alert(isPresented:)` presents only on a
        // false→true edge, and re-evaluating the body with `handoff.askingPayload` still
        // non-nil is not such an edge — it does not retry a presentation SwiftUI already
        // dropped. If a presentation was in fact dropped (e.g. another transition was still
        // in flight when the 600ms wait below fired), `.asking` would otherwise be terminal:
        // every later call here returns immediately via the `.pending` guard below, and
        // `openPaymentURL` used to bail on a fresh tap too, so the feature stayed wedged
        // until the group screen was popped and re-pushed. Force a false→true edge by
        // dropping to `.none` and re-arming to `.pending` on the next runloop turn, but only
        // once `.asking` has been held longer than a short grace window — otherwise a
        // legitimately visible alert would be torn down on every foreground.
        if case .asking(let stuck) = handoff {
            guard let since = askingSince, Date().timeIntervalSince(since) > 2 else { return }
            AppDiagnostics.log(.payment, "handoffPrompt.reDriving", [("provider", stuck.providerName)])
            handoff = .none
            askingSince = nil
            Task { @MainActor in
                // A same-pass `.none` → `.pending` write can coalesce into a single body
                // evaluation and never produce the false→true transition `.alert` needs;
                // yielding a runloop turn first is what makes the edge real.
                try? await Task.sleep(for: .milliseconds(50))
                guard case .none = handoff else { return }
                handoff = .pending(stuck)
                presentHandoffPromptIfReady()
            }
            return
        }

        guard case .pending(let pending) = handoff else { return }
        guard !AppLockService.shared.isLocked else {
            AppDiagnostics.log(.payment, "handoffPrompt.deferred", [
                ("reason", "appLocked"),
                ("provider", pending.providerName)
            ])
            return
        }
        AppDiagnostics.log(.payment, "handoffPrompt.arming", [("provider", pending.providerName)])

        // Presenting synchronously here loses the dialog. When App Lock clears, ContentView
        // animates AppLockView away over 0.3s, and SwiftUI drops a confirmationDialog raised
        // from a descendant while that transition is still in flight. Waiting for the
        // transition to settle is what actually makes it present.
        //
        // `handoff` is never cleared before this sleep — it stays `.pending(pending)`, still
        // holding the payload, for the entire wait, then transitions straight to
        // `.asking(pending)` in one non-destructive step. If this presentation is *also*
        // dropped, the recovery path above is what gets it re-tried — not a re-drive that
        // happens "for free" from a later `.onChange`, which does not exist.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            // Bail if something else already resolved this handoff while asleep (e.g. the
            // group screen was dismissed and reconstructed, or a retry from a subsequent
            // onChange already advanced it) rather than clobbering a newer state.
            guard case .pending(let stillPending) = handoff, stillPending == pending else { return }
            handoff = .asking(stillPending)
            askingSince = Date()
            AppDiagnostics.log(.payment, "handoffPrompt.presented", [("provider", stillPending.providerName)])
        }
    }

    // MARK: - Toolbar

    private var groupMenu: some View {
        Menu {
            Button { openAddExpense() } label: {
                Label("Add Expense", systemImage: "plus")
            }
            Button { showStats = true } label: {
                Label("Stats", systemImage: "chart.bar.fill")
            }
            Button { showGroupSettings = true } label: {
                Label("Manage Group", systemImage: "slider.horizontal.3")
            }

            Divider()

            Menu {
                Button { exportCSV() } label: {
                    Label("Export CSV", systemImage: "tablecells")
                }
                Button { exportPDF() } label: {
                    Label("Export PDF", systemImage: "doc.richtext")
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button { showInvite = true } label: {
                Label("Invite via Email", systemImage: "envelope")
            }
            Button { showInviteLink = true } label: {
                Label("Invite via Link", systemImage: "qrcode")
            }

            Divider()

            if vm.group.isArchived {
                Button {
                    showUnarchiveConfirm = true
                } label: {
                    Label("Unarchive Group", systemImage: "tray.and.arrow.up")
                }
            } else {
                Button(role: .destructive) {
                    showArchiveConfirm = true
                } label: {
                    Label("Archive Group", systemImage: "archivebox")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(AppColors.primary)
                .frame(width: AppSpacing.tapTarget, height: AppSpacing.tapTarget)
        }
        .accessibilityLabel("Group actions")
    }

    // MARK: - Export

    private func openAddExpense() {
        guard NetworkMonitor.shared.isConnected else {
            vm.errorAlert = ErrorAlert(
                title: "You're Offline",
                message: "Connect to the internet before adding an expense."
            )
            return
        }
        showAddExpense = true
    }

    private func exportCSV() {
        let names = vm.memberNames
        let data = ExportService.shared.generateCSV(
            group: vm.group,
            expenses: vm.expenses,
            memberNames: names
        )
        let filename = "\(vm.group.name.sanitizedForFilename)_expenses.csv"
        do {
            let url = try ExportService.shared.writeTemp(data: data, filename: filename)
            shareItem = ExportShareItem(url: url)
        } catch {
            vm.errorAlert = ErrorAlert(title: "Export Failed", message: error.localizedDescription)
        }
    }

    private func exportPDF() {
        let names = vm.memberNames
        let data = ExportService.shared.generatePDF(
            group: vm.group,
            expenses: vm.expenses,
            memberNames: names,
            balances: vm.balances
        )
        let filename = "\(vm.group.name.sanitizedForFilename)_expenses.pdf"
        do {
            let url = try ExportService.shared.writeTemp(data: data, filename: filename)
            shareItem = ExportShareItem(url: url)
        } catch {
            vm.errorAlert = ErrorAlert(title: "Export Failed", message: error.localizedDescription)
        }
    }
}

// MARK: - Group Settings

private struct GroupSettingsView: View {
    @Bindable var vm: GroupViewModel
    let currentUserID: UUID
    let onChanged: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var emoji: String
    @State private var currency: String
    @State private var showInvite = false
    @State private var showInviteLink = false
    @State private var memberToRemove: User?

    private let icons = ["🏠", "✈️", "🍽️", "🎉", "🏖️", "🏢", "🎮", "🚗", "🎵", "💼"]

    init(vm: GroupViewModel, currentUserID: UUID, onChanged: @escaping () async -> Void) {
        self.vm = vm
        self.currentUserID = currentUserID
        self.onChanged = onChanged
        _name = State(initialValue: vm.group.name)
        _emoji = State(initialValue: vm.group.emoji)
        _currency = State(initialValue: vm.group.currency)
    }

    private var isOwner: Bool {
        vm.group.createdBy == currentUserID
    }

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !vm.isLoading else { return false }
        let currencyChanged = vm.canChangeCurrency && currency != vm.group.currency
        return trimmed != vm.group.name || emoji != vm.group.emoji || currencyChanged
    }

    var body: some View {
        NavigationStack {
            XBillScreenContainer(
                horizontalPadding: AppSpacing.lg,
                contentSpacing: AppSpacing.xl,
                bottomPadding: AppSpacing.xl
            ) {
                XBillPageHeader(
                    title: "Manage Group",
                    subtitle: "Edit details, invites, and members.",
                    showsBackButton: true,
                    backAction: { dismiss() }
                )
                .padding(.horizontal, -AppSpacing.lg)

                detailsSection
                inviteSection
                membersSection
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showInvite) {
                InviteMembersView(group: vm.group) {
                    await vm.load()
                    await onChanged()
                }
            }
            .sheet(isPresented: $showInviteLink) {
                GroupInviteView(group: vm.group, currentUserID: currentUserID)
            }
            .confirmationDialog(
                "Remove Member?",
                isPresented: Binding(
                    get: { memberToRemove != nil },
                    set: { if !$0 { memberToRemove = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    guard let member = memberToRemove else { return }
                    Task {
                        await vm.removeMember(userID: member.id)
                        if vm.errorAlert == nil {
                            await onChanged()
                            memberToRemove = nil
                        }
                    }
                }
                Button("Cancel", role: .cancel) { memberToRemove = nil }
            } message: {
                if let memberToRemove {
                    Text("\(memberToRemove.displayName) will lose access to this group. Their historical expenses and splits stay visible.")
                }
            }
        }
        .errorAlert(item: $vm.errorAlert)
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            XBillSectionHeader("Details")
            XBillFormSection {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    XBillTextField(placeholder: "Group name", text: $name)
                        .accessibilityLabel("Group name")
                        .accessibilityIdentifier("xBill.groupSettings.nameField")

                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Icon")
                            .font(.appCaptionMedium)
                            .foregroundStyle(AppColors.textSecondary)
                        XBillIconPickerGrid(icons: icons, selectedIcon: $emoji)
                    }

                    HStack(spacing: AppSpacing.md) {
                        Text("Currency")
                            .font(.appBody)
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Picker("Currency", selection: $currency) {
                            ForEach(ExchangeRateService.commonCurrencies, id: \.self) { code in
                                Text(code).tag(code)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(AppColors.primary)
                        .disabled(!vm.canChangeCurrency)
                        .accessibilityIdentifier("xBill.groupSettings.currencyPicker")
                    }
                    if !vm.canChangeCurrency {
                        Text("Currency is locked after the first expense to keep historical amounts accurate.")
                            .font(.appCaption)
                            .foregroundStyle(AppColors.textSecondary)
                            .accessibilityIdentifier("xBill.groupSettings.currencyLockedMessage")
                    }

                    XBillPrimaryButton(
                        title: "Save Changes",
                        icon: "checkmark",
                        isLoading: vm.isLoading,
                        isDisabled: !canSave
                    ) {
                        Task {
                            await vm.updateGroupDetails(name: name, emoji: emoji, currency: currency)
                            name = vm.group.name
                            emoji = vm.group.emoji
                            currency = vm.group.currency
                            await onChanged()
                        }
                    }
                    .accessibilityIdentifier("xBill.groupSettings.saveButton")
                }
            }
        }
    }

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            XBillSectionHeader("Invites")
            XBillActionCard(
                icon: "envelope.fill",
                title: "Invite by Email",
                subtitle: "Send a group invite to a member."
            ) {
                showInvite = true
            }
            .accessibilityIdentifier("xBill.groupSettings.inviteEmailButton")
            XBillActionCard(
                icon: "qrcode",
                title: "Invite Link",
                subtitle: "Share a reusable link or QR code."
            ) {
                showInviteLink = true
            }
            .accessibilityIdentifier("xBill.groupSettings.inviteLinkButton")
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            XBillSectionHeader("Members", subtitle: "\(vm.activeMembers.count) active · \(vm.members.count) historical")
            XBillFormSection {
                VStack(spacing: 0) {
                    ForEach(Array(vm.members.enumerated()), id: \.element.id) { index, member in
                        memberRow(member)
                        if index < vm.members.count - 1 {
                            Divider()
                                .overlay(AppColors.border)
                        }
                    }

                    if vm.members.isEmpty {
                        Text("Members will appear after the group finishes loading.")
                            .font(.appCaption)
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if !isOwner {
                Text("Only the group owner can remove members.")
                    .font(.appCaption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private func memberRow(_ member: User) -> some View {
        HStack(spacing: AppSpacing.md) {
            AvatarView(name: member.displayName, url: member.avatarURL, size: XBillIcon.avatarSm)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(member.displayName)
                    .font(.appBody)
                    .foregroundStyle(AppColors.textPrimary)
                if !member.email.isEmpty {
                    Text(member.email)
                        .font(.appCaption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()

            if vm.group.createdBy == member.id {
                Text("Owner")
                    .font(.appCaptionMedium)
                    .foregroundStyle(AppColors.primary)
                    .padding(.horizontal, AppSpacing.sm)
                    .frame(minHeight: 28)
                    .background(AppColors.surfaceSoft)
                    .clipShape(Capsule())
            } else if isOwner {
                Button(role: .destructive) {
                    memberToRemove = member
                } label: {
                    Image(systemName: member.isActive ? "person.crop.circle.badge.minus" : "clock.badge")
                        .font(.appTitle)
                        .foregroundStyle(member.isActive ? AppColors.error : AppColors.textTertiary)
                        .frame(width: AppSpacing.tapTarget, height: AppSpacing.tapTarget)
                }
                .buttonStyle(.plain)
                .disabled(!member.isActive)
                .accessibilityLabel("Remove \(member.displayName)")
            }
            if !member.isActive {
                Text("Inactive")
                    .font(.appCaptionMedium)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, AppSpacing.sm)
                    .frame(minHeight: 28)
                    .background(AppColors.surfaceSoft)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, AppSpacing.sm)
    }
}

// MARK: - Filter Chip

private struct ExpenseFilterChip: View {
    let label: String
    var category: Expense.Category? = nil
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: XBillSpacing.xs) {
                if let category {
                    XBillCategoryIcon(category: category, size: 22)
                }
                Text(label)
                    .font(.xbillLabel)
                    .foregroundStyle(isSelected ? Color.brandPrimary : Color.textSecondary)
            }
            .padding(.horizontal, XBillSpacing.md)
            .padding(.vertical, XBillSpacing.xs)
            .background(isSelected ? Color.brandSurface : Color.bgTertiary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.brandPrimary : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .frame(minHeight: AppSpacing.tapTarget)
    }
}

// MARK: - Export helpers

struct ExportShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private extension String {
    var sanitizedForFilename: String {
        self.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "_")
            .lowercased()
    }
}

#Preview {
    NavigationStack {
        GroupDetailView(
            group: BillGroup(
                id: UUID(), name: "Weekend Trip", emoji: "✈️",
                createdBy: UUID(), isArchived: false,
                currency: "USD", createdAt: Date()
            ),
            currentUserID: UUID()
        )
    }
}
