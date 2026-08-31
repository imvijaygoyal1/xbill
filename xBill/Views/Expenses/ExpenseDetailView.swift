//
//  ExpenseDetailView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.vijaygoyal.xbill", category: "ExpenseDetailView")

struct ExpenseDetailView: View {
    let expense: Expense
    let members: [User]
    let currency: String
    let groupName: String
    let currentUserID: UUID
    var onUpdated: ((Expense) -> Void)? = nil
    var onDeleted: (() -> Void)? = nil

    @State private var splits: [Split] = []
    @State private var isLoading = false
    @State private var error: AppError?

    // Comments
    @State private var comments: [Comment] = []
    @State private var isLoadingComments = false
    @State private var newCommentText = ""
    @State private var isPostingComment = false

    // Edit sheet state
    @State private var isEditing = false
    @State private var editTitle: String = ""
    @State private var editAmountText: String = ""
    @State private var editCategory: Expense.Category = .other
    @State private var editNotes: String = ""
    @State private var editPayerID: UUID? = nil
    /// SPLIT-01. Seeded from the existing splits when the sheet opens, so a member who joined the
    /// group after this expense was created can be ticked onto it.
    @State private var splitEditor: SplitEditor? = nil
    /// Whether the user touched the split section. If they did not, an amount change is rescaled
    /// proportionally (SPLIT-02) rather than re-derived — which preserves a deliberate 70/30 that
    /// the stored data cannot otherwise describe.
    @State private var splitsEdited = false
    @State private var isSaving = false

    // Delete state
    @State private var showDeleteConfirm = false
    @State private var commentToDelete: Comment?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private func memberName(_ id: UUID) -> String {
        members.first(where: { $0.id == id })?.displayName ?? "Unknown"
    }

    private func memberAvatar(_ id: UUID) -> URL? {
        members.first(where: { $0.id == id })?.avatarURL
    }

    var body: some View {
        List {
            // Header
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(expense.category.displayName, systemImage: expense.category.systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Text(expense.amount.formatted(currencyCode: currency))
                        .font(.largeTitle.bold())

                    // Show original foreign currency amount if applicable
                    if let origAmount = expense.originalAmount,
                       let origCurrency = expense.originalCurrency,
                       origCurrency != currency {
                        Text("Originally \(origAmount.formatted(currencyCode: origCurrency))")
                            .font(.caption)
                            .foregroundStyle(Color.brandPrimary)
                    }

                    HStack {
                        Text("Paid by")
                            .foregroundStyle(.secondary)
                        let payerName = expense.payerID.map { memberName($0) } ?? "Unknown"
                        AvatarView(name: payerName, url: expense.payerID.flatMap { memberAvatar($0) }, size: 22)
                        Text(payerName)
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)

                    Text(expense.createdAt.shortFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            // Notes
            if let notes = expense.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                        .font(.subheadline)
                }
            }

            // Splits
            Section("Split Between") {
                if isLoading {
                    ProgressView()
                } else {
                    ForEach(splits) { split in
                        HStack {
                            AvatarView(
                                name: memberName(split.userID),
                                url: memberAvatar(split.userID),
                                size: 32
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(memberName(split.userID))
                                    .font(.subheadline)
                            }
                            Spacer()
                            Text(split.amount.formatted(currencyCode: currency))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            // Comments
            Section("Comments") {
                if isLoadingComments {
                    ProgressView()
                } else if comments.isEmpty {
                    Text("No comments yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(comments) { comment in
                        commentRow(comment)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if comment.userID == currentUserID {
                                    Button(role: .destructive) {
                                        commentToDelete = comment
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            commentInputBar
        }
        .accessibilityIdentifier("xBill.expenseDetail.screen")
        .navigationTitle(expense.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { reportExpense() } label: {
                        Label("Report Content", systemImage: "exclamationmark.bubble")
                    }
                    Button { openEditSheet() } label: {
                        Label("Edit Expense", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete Expense", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            isLoading = true
            isLoadingComments = true
            async let fetchedSplits   = ExpenseService.shared.fetchSplits(expenseID: expense.id)
            async let fetchedComments = CommentService.shared.fetchComments(expenseID: expense.id)
            do { splits   = try await fetchedSplits   } catch { self.error = AppError.from(error) }
            do { comments = try await fetchedComments } catch { self.error = AppError.from(error) }
            isLoading = false
            isLoadingComments = false
        }
        .task(id: expense.id) {
            do {
                let stream = try await CommentService.shared.commentChanges(expenseID: expense.id)
                for await _ in stream {
                    do {
                        comments = try await CommentService.shared.fetchComments(expenseID: expense.id)
                    } catch {
                        logger.error("Comment refresh after realtime event failed: \(error, privacy: .public)")
                    }
                }
            } catch {
                logger.error("Realtime comment subscription failed for expense \(expense.id, privacy: .public): \(error, privacy: .public)")
            }
        }
        .confirmationDialog("Delete this expense?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    await MainActor.run { isLoading = true }
                    onDeleted?()
                    await MainActor.run { isLoading = false }
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the expense and all its splits. This cannot be undone.")
        }
        .confirmationDialog("Delete Comment?", isPresented: Binding(
            get: { commentToDelete != nil },
            set: { if !$0 { commentToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let comment = commentToDelete else { return }
                Task {
                    do {
                        try await CommentService.shared.deleteComment(id: comment.id)
                        comments.removeAll { $0.id == comment.id }
                    } catch {
                        self.error = AppError.from(error)
                    }
                    commentToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { commentToDelete = nil }
        } message: {
            Text("This will permanently delete your comment.")
        }
        .sheet(isPresented: $isEditing) {
            editSheet
        }
        .errorAlert(error: $error)
    }

    // MARK: - Comment Row

    private func commentRow(_ comment: Comment) -> some View {
        HStack(alignment: .top, spacing: XBillSpacing.sm) {
            AvatarView(
                name: memberName(comment.userID),
                url: memberAvatar(comment.userID),
                size: 32
            )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: XBillSpacing.xs) {
                    Text(memberName(comment.userID))
                        .font(.caption.bold())
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text(comment.createdAt.relativeFormatted)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(comment.text)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Comment Input Bar

    private var commentInputBar: some View {
        HStack(spacing: XBillSpacing.sm) {
            TextField("Add a comment…", text: $newCommentText, axis: .vertical)
                .lineLimit(1...4)
                .accessibilityIdentifier("xBill.expenseDetail.commentField")
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.inputBg)
                .clipShape(RoundedRectangle(cornerRadius: XBillRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: XBillRadius.md)
                        .stroke(Color.inputBorder, lineWidth: 1)
                )

            Button {
                Task { await postComment() }
            } label: {
                if isPostingComment {
                    ProgressView()
                        .frame(width: 36, height: 36)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.secondary
                            : Color.brandPrimary)
                }
            }
            .disabled(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPostingComment)
            .accessibilityLabel("Post comment")
            .accessibilityIdentifier("xBill.expenseDetail.postCommentButton")
        }
        .padding(.horizontal, XBillSpacing.base)
        .padding(.vertical, XBillSpacing.sm)
        .background(.regularMaterial)
    }

    // MARK: - Edit Sheet

    private var editSheet: some View {
        NavigationStack {
            Form {
                Section("Expense") {
                    TextField("What was it for?", text: $editTitle)

                    HStack {
                        Text(currency).foregroundStyle(.secondary)
                        TextField("0.00", text: $editAmountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    Picker("Category", selection: $editCategory) {
                        ForEach(Expense.Category.allCases, id: \.self) { cat in
                            Label(cat.displayName, systemImage: cat.systemImage).tag(cat)
                        }
                    }
                }

                Section("Paid By") {
                    Picker("Paid by", selection: $editPayerID) {
                        ForEach(members) { member in
                            Text(member.displayName).tag(Optional(member.id))
                        }
                    }
                }

                if let editor = splitEditor {
                    Section("Split Between") {
                        Picker("How to split", selection: Binding(
                            get: { editor.strategy },
                            set: { editor.strategy = $0; splitsEdited = true; editor.recompute() }
                        )) {
                            ForEach(SplitStrategy.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("xBill.editExpense.splitStrategyPicker")

                        // CRASH-01: iterate values, never `ForEach($editor.inputs)`. Element
                        // bindings are index-backed and UIKit reads them back during a deferred
                        // update pass; every edit resolves its row by id instead.
                        ForEach(editor.inputs) { input in
                            SplitParticipantRow(
                                input: input,
                                strategy: editor.strategy,
                                currency: currency,
                                // An expense may legitimately be split with someone who has left.
                                subtitle: departedSubtitle(for: input.userID),
                                idPrefix: "xBill.editExpense",
                                onToggle: { editor.toggle(participantID: input.userID); splitsEdited = true },
                                onAmount: { editor.setAmount($0, participantID: input.userID); splitsEdited = true },
                                onPercentage: { editor.setPercentage($0, participantID: input.userID); splitsEdited = true },
                                onShares: { editor.adjustShares(by: $0, participantID: input.userID); splitsEdited = true }
                            )
                        }

                        if let progress = editor.percentageProgress {
                            // Shown from the moment percentage mode is chosen, not only after an
                            // edit: the user needs to know 100% is outstanding before they start.
                            PercentageProgressHint(progress: progress)
                        } else if splitsEdited, let problem = editor.validationError(for: editedAmount) {
                            Text(problem)
                                .font(.caption)
                                .foregroundStyle(Color.moneyNegative)
                        }
                    }
                }

                Section("Notes (optional)") {
                    TextField("Add a note…", text: $editNotes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Edit Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isEditing = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await saveEdit() } }
                        .disabled(editTitle.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                        .overlay {
                            if isSaving {
                                ProgressView()
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }
        }
    }

    // MARK: - Helpers

    /// Seeded fresh each time so a cancelled edit leaves nothing behind.
    /// The amount currently typed into the sheet, for validating against as it changes.
    private var editedAmount: Decimal {
        Decimal(string: editAmountText.replacingOccurrences(of: ",", with: ".")) ?? expense.amount
    }

    /// Hoisted out of the row's argument list: an inline ternary there exceeded the
    /// type-checker's budget for the enclosing expression.
    private func departedSubtitle(for userID: UUID) -> String? {
        members.contains { $0.id == userID } ? nil : "No longer in this group"
    }

    private func seedSplitEditor() {
        let total = Decimal(string: editAmountText.replacingOccurrences(of: ",", with: ".")) ?? expense.amount
        splitEditor  = SplitEditor.forEditing(existingSplits: splits, members: members, total: total)
        splitsEdited = false
    }

    private func openEditSheet() {
        editTitle      = expense.title
        var amountCopy = expense.amount
        var rounded    = Decimal()
        NSDecimalRound(&rounded, &amountCopy, 2, .bankers)
        editAmountText = "\(rounded)"
        editCategory   = expense.category
        editNotes      = expense.notes ?? ""
        editPayerID    = expense.payerID
        seedSplitEditor()
        isEditing      = true
    }

    private func reportExpense() {
        openURL(XBillURLs.supportMailURL(
            subject: "xBill content report",
            body: """
            Please review this content report.

            Group: \(groupName)
            Group ID: \(expense.groupID.uuidString)
            Expense: \(expense.title)
            Expense ID: \(expense.id.uuidString)
            Reporting user ID: \(currentUserID.uuidString)

            Describe the issue:
            """
        ))
    }

    /// The token to send as `p_expected_updated_at`.
    ///
    /// A nil token means "skip the check" on the server. That is correct for clients on 1.0–1.5,
    /// and WRONG here: a nil can also come from a `CacheService` entry written before the column
    /// existed, and that first edit after upgrading — right when the app has just reopened — is
    /// exactly the one most likely to race. So a nil forces a re-read instead of reaching the
    /// server as "no check".
    private func currentToken() async throws -> String? {
        if let token = expense.updatedAt { return token }
        return try await ExpenseService.shared.fetchExpense(id: expense.id).updatedAt
    }

    /// Refuse-and-reload. Nothing is merged and nothing is invented: the user sees the current
    /// server state and re-applies their edit if they still want it.
    ///
    /// Presented through this view's own `error` surface, because feedback for a pushed screen
    /// has to be reachable from that screen — an alert raised on the parent is invisible, or
    /// flashes and dies mid-transition.
    private func handleEditConflict() async {
        isEditing = false
        do {
            let fresh = try await ExpenseService.shared.fetchExpense(id: expense.id)
            let freshSplits = try await ExpenseService.shared.fetchSplits(expenseID: expense.id)
            splits = freshSplits
            onUpdated?(fresh)

            let who = fresh.updatedBy.flatMap { id in
                members.first(where: { $0.id == id })?.displayName
            } ?? "Someone"
            error = .validationFailed(
                "\(who) changed this expense while you were editing. "
                + "It is now \(fresh.title), \(fresh.amount.formatted(currencyCode: fresh.currency)). "
                + "Your changes weren't saved — review theirs and try again.")
        } catch {
            self.error = AppError.from(error)
        }
    }

    private func saveEdit() async {
        guard let payerID = editPayerID,
              let amount = Decimal(string: editAmountText.replacingOccurrences(of: ",", with: ".")),
              amount > .zero else { return }
        isSaving = true
        defer { isSaving = false }
        let updated = Expense(
            id:                   expense.id,
            groupID:              expense.groupID,
            title:                editTitle.trimmingCharacters(in: .whitespaces),
            amount:               amount,
            currency:             currency,
            payerID:              payerID,
            category:             editCategory,
            notes:                editNotes.isEmpty ? nil : editNotes,
            receiptURL:           expense.receiptURL,
            originalAmount:       expense.originalAmount,
            originalCurrency:     expense.originalCurrency,
            recurrence:           expense.recurrence,
            nextOccurrenceDate:   expense.nextOccurrenceDate,
            createdAt:            expense.createdAt
        )
        do {
            // Two paths, deliberately.
            //
            // If the user TOUCHED the split section (SPLIT-01), their choice is authoritative —
            // they picked participants and a strategy, so use exactly that.
            //
            // If they did not, the split is rescaled PROPORTIONALLY (SPLIT-02) rather than
            // re-derived. The strategy is not persisted, so re-deriving would have to guess, and
            // guessing "equal" would silently flatten a deliberate 70/30 that the user never
            // opened the section to change.
            if splitsEdited, let editor = splitEditor {
                if let problem = editor.validationError(for: amount) {
                    self.error = AppError.validationFailed(problem)
                    return
                }
                let chosen = editor.includedInputs
                guard !chosen.isEmpty else {
                    self.error = AppError.validationFailed("Choose at least one person to split this with.")
                    return
                }
                let token = try await currentToken()
                let saved: Expense
                do {
                    saved = try await ExpenseService.shared.updateExpenseWithSplits(
                        updated, splits: chosen, expectedUpdatedAt: token)
                } catch let e where AppError.isEditConflict(e) {
                    await handleEditConflict()
                    return
                }
                splits = chosen.map {
                    Split(id: UUID(), expenseID: expense.id, userID: $0.userID,
                          amount: $0.amount)
                }
                onUpdated?(saved)
                isEditing = false
                return
            }

            let rescaled = SplitCalculator.rescale(splits: splits,
                                                   from: expense.amount,
                                                   to: amount,
                                                   payerID: payerID)
            guard let rescaled else {
                // `add_expense_with_splits` requires at least one split, so an expense can never
                // legitimately have none — an empty array here means they have not finished
                // loading. Saving anyway would write a split set built from nothing.
                self.error = AppError.validationFailed(
                    "This expense's shares haven't finished loading. Close it, reopen it, and try again.")
                return
            }
            // `SplitInput` carries display fields the RPC does not use; only userID and amount
            // cross the wire.
            let inputs = rescaled.map { split -> SplitInput in
                var input = SplitInput(userID: split.userID,
                                       displayName: members.first { $0.id == split.userID }?.displayName ?? "")
                input.amount = split.amount
                return input
            }
            let token = try await currentToken()
            let saved: Expense
            do {
                saved = try await ExpenseService.shared.updateExpenseWithSplits(
                    updated, splits: inputs, expectedUpdatedAt: token)
            } catch let e where AppError.isEditConflict(e) {
                await handleEditConflict()
                return
            }
            splits = rescaled
            onUpdated?(saved)
            isEditing = false
        } catch {
            self.error = AppError.from(error)
        }
    }

    private func postComment() async {
        let text = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isPostingComment = true
        defer { isPostingComment = false }
        do {
            let commenterName = members.first(where: { $0.id == currentUserID })?.displayName ?? "Someone"
            let comment = try await CommentService.shared.addComment(
                expenseID:     expense.id,
                userID:        currentUserID,
                text:          text,
                expenseTitle:  expense.title,
                groupID:       expense.groupID,
                groupName:     groupName,
                commenterName: commenterName
            )
            comments.append(comment)
            newCommentText = ""
            HapticManager.success()
        } catch {
            self.error = AppError.from(error)
        }
    }
}

#Preview {
    NavigationStack {
        ExpenseDetailView(
            expense: Expense(
                id: UUID(), groupID: UUID(), title: "Dinner",
                amount: 120.50, currency: "USD", payerID: UUID(),
                category: .food, notes: "Great sushi place!",
                receiptURL: nil, recurrence: .none, createdAt: Date()
            ),
            members: [],
            currency: "USD",
            groupName: "Weekend Trip",
            currentUserID: UUID()
        )
    }
}
