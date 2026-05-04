//
//  InviteMembersView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

// MARK: - InviteMembersView

struct InviteMembersView: View {
    let group: BillGroup
    let onDone: () async -> Void

    @State private var emailInput: String = ""
    @State private var pendingInvites: [String] = []
    @State private var xBillUsers: [String: User] = [:]   // email → User (already on xBill)
    @State private var isLoading: Bool = false
    @State private var isLookingUp: Bool = false
    @State private var showContactPicker: Bool = false
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

                    Button {
                        showContactPicker = true
                    } label: {
                        Label("Import from Contacts", systemImage: "person.crop.circle.badge.plus")
                            .foregroundStyle(Color.brandPrimary)
                    }
                    .disabled(isLookingUp)
                } header: {
                    Text("Invite by email")
                } footer: {
                    Text("They'll receive a link to join \(group.name).")
                }

                if !pendingInvites.isEmpty {
                    Section("Pending Invites") {
                        ForEach(pendingInvites, id: \.self) { email in
                            HStack {
                                Label(email, systemImage: "envelope")
                                Spacer()
                                if xBillUsers[email] != nil {
                                    Text("On xBill")
                                        .font(.xbillCaption)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.brandAccent)
                                        .clipShape(Capsule())
                                }
                            }
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
                    if isLoading {
                        ProgressView()
                    } else {
                        Button("Send \(pendingInvites.count) Invite\(pendingInvites.count == 1 ? "" : "s")") {
                            Task { await sendInvites() }
                        }
                        .disabled(pendingInvites.isEmpty)
                    }
                }
            }
            .sheet(isPresented: $showContactPicker) {
                ContactPickerRepresentable { emails in
                    showContactPicker = false
                    addEmails(emails)
                }
                .ignoresSafeArea()
            }
        }
        .errorAlert(error: $error)
    }

    private func addEmail() {
        let trimmed = emailInput.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty, !pendingInvites.contains(trimmed) else { return }
        pendingInvites.append(trimmed)
        emailInput = ""
        Task { await lookupXBillUsers([trimmed]) }
    }

    private func addEmails(_ emails: [String]) {
        let newEmails = emails.filter { !pendingInvites.contains($0) }
        pendingInvites.append(contentsOf: newEmails)
        if !newEmails.isEmpty {
            Task { await lookupXBillUsers(newEmails) }
        }
    }

    private func lookupXBillUsers(_ emails: [String]) async {
        isLookingUp = true
        defer { isLookingUp = false }
        let found = (try? await GroupService.shared.lookupProfilesByEmail(emails)) ?? []
        for user in found {
            xBillUsers[user.email] = user
        }
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
