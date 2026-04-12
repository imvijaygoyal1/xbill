import SwiftUI

struct ExpenseDetailView: View {
    let expense: Expense
    let members: [User]
    let currency: String
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
    @State private var isSaving = false

    // Delete state
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss

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

                    Text(expense.amount.formatted(currencyCode: currency))
                        .font(.largeTitle.bold())

                    HStack {
                        Text("Paid by")
                            .foregroundStyle(.secondary)
                        AvatarView(name: memberName(expense.payerID), url: memberAvatar(expense.payerID), size: 22)
                        Text(memberName(expense.payerID))
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
                                if split.isSettled {
                                    Text("Settled \(split.settledAt?.relativeFormatted ?? "")")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }
                            Spacer()
                            Text(split.amount.formatted(currencyCode: currency))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(split.isSettled ? .secondary : .primary)
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
                    }
                    .onDelete { offsets in
                        for comment in offsets.map({ comments[$0] }) {
                            guard comment.userID == currentUserID else { continue }
                            Task {
                                try? await CommentService.shared.deleteComment(id: comment.id)
                                comments.removeAll { $0.id == comment.id }
                            }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            commentInputBar
        }
        .navigationTitle(expense.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
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
            defer { isLoading = false }
            do {
                splits = try await ExpenseService.shared.fetchSplits(expenseID: expense.id)
            } catch {
                self.error = AppError.from(error)
            }
        }
        .task {
            isLoadingComments = true
            defer { isLoadingComments = false }
            do {
                comments = try await CommentService.shared.fetchComments(expenseID: expense.id)
            } catch {
                self.error = AppError.from(error)
            }
        }
        .task(id: expense.id) {
            guard let stream = try? await CommentService.shared.commentChanges(expenseID: expense.id) else { return }
            for await _ in stream {
                if let fresh = try? await CommentService.shared.fetchComments(expenseID: expense.id) {
                    comments = fresh
                }
            }
        }
        .confirmationDialog("Delete this expense?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                onDeleted?()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the expense and all its splits. This cannot be undone.")
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
                        .overlay { if isSaving { ProgressView() } }
                }
            }
        }
    }

    // MARK: - Helpers

    private func openEditSheet() {
        editTitle      = expense.title
        editAmountText = NSDecimalNumber(decimal: expense.amount).stringValue
        editCategory   = expense.category
        editNotes      = expense.notes ?? ""
        editPayerID    = expense.payerID
        isEditing      = true
    }

    private func saveEdit() async {
        guard let payerID = editPayerID,
              let amount = Decimal(string: editAmountText.replacingOccurrences(of: ",", with: ".")),
              amount > .zero else { return }
        isSaving = true
        defer { isSaving = false }
        let updated = Expense(
            id:         expense.id,
            groupID:    expense.groupID,
            title:      editTitle.trimmingCharacters(in: .whitespaces),
            amount:     amount,
            currency:   currency,
            payerID:    payerID,
            category:   editCategory,
            notes:      editNotes.isEmpty ? nil : editNotes,
            receiptURL: expense.receiptURL,
            createdAt:  expense.createdAt
        )
        do {
            let saved = try await ExpenseService.shared.updateExpense(updated)
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
            let comment = try await CommentService.shared.addComment(
                expenseID: expense.id,
                userID: currentUserID,
                text: text
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
                receiptURL: nil, createdAt: Date()
            ),
            members: [],
            currency: "USD",
            currentUserID: UUID()
        )
    }
}
