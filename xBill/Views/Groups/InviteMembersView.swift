import SwiftUI

struct InviteMembersView: View {
    let group: BillGroup
    let onDone: () async -> Void

    @State private var emailInput: String = ""
    @State private var pendingInvites: [String] = []
    @State private var isLoading: Bool = false
    @State private var error: AppError?

    @Environment(\.dismiss) private var dismiss

    private var isValidEmail: Bool {
        emailInput.contains("@") && emailInput.contains(".")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Email address", text: $emailInput)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        Button("Add") { addEmail() }
                            .disabled(!isValidEmail)
                    }
                } header: {
                    Text("Invite by email")
                } footer: {
                    Text("They'll receive a link to join \(group.name).")
                }

                if !pendingInvites.isEmpty {
                    Section("Pending Invites") {
                        ForEach(pendingInvites, id: \.self) { email in
                            Label(email, systemImage: "envelope")
                        }
                        .onDelete { indexSet in
                            pendingInvites.remove(atOffsets: indexSet)
                        }
                    }
                }
            }
            .navigationTitle("Invite Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send \(pendingInvites.count) Invite\(pendingInvites.count == 1 ? "" : "s")") {
                        Task { await sendInvites() }
                    }
                    .disabled(pendingInvites.isEmpty || isLoading)
                }
            }
        }
        .errorAlert(error: $error)
    }

    private func addEmail() {
        let trimmed = emailInput.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty, !pendingInvites.contains(trimmed) else { return }
        pendingInvites.append(trimmed)
        emailInput = ""
    }

    private func sendInvites() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let currentUser = try await AuthService.shared.currentUser()
            try await GroupService.shared.inviteMembers(
                emails: pendingInvites,
                groupName: group.name,
                groupEmoji: group.emoji,
                inviterName: currentUser.displayName
            )
            await onDone()
            dismiss()
        } catch {
            self.error = AppError.from(error)
        }
    }
}

#Preview {
    InviteMembersView(
        group: BillGroup(
            id: UUID(), name: "Test", emoji: "💸",
            createdBy: UUID(), isArchived: false,
            currency: "USD", createdAt: Date()
        ),
        onDone: { }
    )
}
