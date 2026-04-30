//
//  AddIOUView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct AddIOUView: View {
    let currentUserID: UUID
    var preselectedFriendID: UUID? = nil
    var preselectedFriend: User?  = nil
    let onSaved: () async -> Void

    @State private var emailText: String = ""
    @State private var foundUser: User?  = nil
    @State private var isSearching = false
    @State private var searchError: String?

    @State private var amountText: String = ""
    @State private var currency: String = "USD"
    @State private var description: String = ""
    @State private var iOwe: Bool = true  // true = I owe them, false = they owe me

    @State private var isSaving = false
    @State private var error: AppError?
    @Environment(\.dismiss) private var dismiss

    private var targetUser: User? { preselectedFriend ?? foundUser }

    private var amount: Decimal {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")) ?? .zero
    }

    private var canSave: Bool {
        targetUser != nil && amount > .zero
    }

    var body: some View {
        NavigationStack {
            Form {
                // Friend search (hidden if preselected)
                if preselectedFriend == nil {
                    Section("Who?") {
                        HStack {
                            TextField("Their email address", text: $emailText)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                            if isSearching {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Button("Find") { Task { await searchUser() } }
                                    .disabled(emailText.isEmpty)
                            }
                        }
                        if let msg = searchError {
                            Text(msg).font(.caption).foregroundStyle(.red)
                        }
                        if let user = foundUser {
                            HStack {
                                AvatarView(name: user.displayName, url: user.avatarURL, size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.displayName).font(.subheadline.bold())
                                    Text(user.email).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                } else if let friend = preselectedFriend {
                    Section("With") {
                        HStack {
                            AvatarView(name: friend.displayName, url: friend.avatarURL, size: 32)
                            Text(friend.displayName).font(.subheadline.bold())
                        }
                    }
                }

                Section("Amount") {
                    HStack {
                        // Currency picker
                        Menu {
                            ForEach(ExchangeRateService.commonCurrencies, id: \.self) { code in
                                Button(code) { currency = code }
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Text(currency).foregroundStyle(Color.brandPrimary).bold()
                                Image(systemName: "chevron.down").font(.caption2)
                                    .foregroundStyle(Color.brandPrimary)
                            }
                        }
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                    }
                }

                Section("Who owes?") {
                    let otherName = targetUser?.displayName ?? "them"
                    Picker("Direction", selection: $iOwe) {
                        Text("I owe \(otherName)").tag(true)
                        Text("\(otherName) owes me").tag(false)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Note (optional)") {
                    TextField("What's this for?", text: $description)
                }
            }
            .navigationTitle("Add IOU")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!canSave || isSaving)
                        .overlay { if isSaving { ProgressView() } }
                }
            }
            .errorAlert(error: $error)
        }
    }

    // MARK: - Actions

    private func searchUser() async {
        let email = emailText.trimmingCharacters(in: .whitespaces)
        guard !email.isEmpty else { return }
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            if let user = try await IOUService.shared.fetchUserByEmail(email) {
                guard user.id != currentUserID else {
                    searchError = "You can't add yourself."
                    return
                }
                foundUser = user
            } else {
                searchError = "No xBill account found for \(email)."
            }
        } catch {
            searchError = AppError.from(error).localizedDescription
        }
    }

    private func save() async {
        guard let other = targetUser, amount > .zero else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            // iOwe = true → I am borrower, other is lender
            // iOwe = false → I am lender, other is borrower
            let lenderID   = iOwe ? other.id      : currentUserID
            let borrowerID = iOwe ? currentUserID : other.id

            _ = try await IOUService.shared.createIOU(
                createdBy:   currentUserID,
                lenderID:    lenderID,
                borrowerID:  borrowerID,
                amount:      amount,
                currency:    currency,
                description: description.isEmpty ? nil : description
            )
            HapticManager.success()
            await onSaved()
            dismiss()
        } catch {
            self.error = AppError.from(error)
        }
    }
}
