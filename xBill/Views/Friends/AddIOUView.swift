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
    var preselectedFriend: User?   = nil
    let onSaved: () async -> Void

    // Friend picker state
    @State private var friends:        [User] = []
    @State private var isLoadingFriends = false
    @State private var selectedFriend: User? = nil
    @State private var showEmailSearch = false

    // Email search fallback state
    @State private var emailText:  String = ""
    @State private var foundUser:  User?  = nil
    @State private var isSearching = false
    @State private var searchError: String?

    @State private var amountText: String = ""
    @State private var currency:   String = "USD"
    @State private var description: String = ""
    @State private var iOwe: Bool = true

    @State private var isSaving = false
    @State private var error: AppError?
    @Environment(\.dismiss) private var dismiss

    private var targetUser: User? { preselectedFriend ?? selectedFriend ?? foundUser }

    private var amount: Decimal {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")) ?? .zero
    }

    private var canSave: Bool {
        targetUser != nil && amount > .zero
    }

    var body: some View {
        NavigationStack {
            XBillScreenBackground {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        amountHero
                        personSection
                        directionSection
                        noteSection
                    }
                    .padding(AppSpacing.md)
                    .padding(.bottom, AppSpacing.floatingActionBottomPadding)
                }
            }
            .navigationTitle("Add IOU")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                XBillPrimaryButton(
                    title: "Save IOU",
                    icon: "checkmark",
                    isLoading: isSaving,
                    isDisabled: !canSave
                ) {
                    Task { await save() }
                }
                .padding(AppSpacing.md)
                .background(.ultraThinMaterial)
            }
            .task { await loadFriends() }
            .errorAlert(error: $error)
        }
    }

    // MARK: - Amount

    private var amountHero: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("AMOUNT")
                .font(.appCaptionMedium)
                .tracking(1.08)
                .foregroundStyle(AppColors.textSecondary)

            HStack(alignment: .center, spacing: AppSpacing.md) {
                XBillReceiptIcon(size: 64)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                        Menu {
                            ForEach(ExchangeRateService.commonCurrencies, id: \.self) { code in
                                Button(code) { currency = code }
                            }
                        } label: {
                            HStack(spacing: AppSpacing.xs) {
                                Text(currency)
                                    .font(.appAmountSm)
                                Image(systemName: "chevron.down")
                                    .font(.appCaptionMedium)
                            }
                            .foregroundStyle(AppColors.primary)
                            .frame(minHeight: AppSpacing.tapTarget)
                        }

                        TextField("0.00", text: $amountText)
                            .font(.appAmount)
                            .keyboardType(.decimalPad)
                            .foregroundStyle(AppColors.textPrimary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .xbillCard()
    }

    // MARK: - Person Section

    @ViewBuilder
    private var personSection: some View {
        if let friend = preselectedFriend {
            formCard("WITH") {
                HStack {
                    AvatarView(name: friend.displayName, url: friend.avatarURL, size: AppSpacing.tapTarget)
                    Text(friend.displayName)
                        .font(.appTitle)
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
        } else {
            formCard("PERSON") {
                if let selected = selectedFriend ?? foundUser {
                    // Confirmed person — show with clear button
                    HStack {
                        AvatarView(name: selected.displayName, url: selected.avatarURL, size: AppSpacing.tapTarget)
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text(selected.displayName)
                                .font(.appTitle)
                                .foregroundStyle(AppColors.textPrimary)
                            Text(selected.email)
                                .font(.appCaption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        Spacer()
                        Button {
                            selectedFriend = nil
                            foundUser = nil
                            emailText = ""
                            searchError = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AppColors.textSecondary)
                                .frame(width: AppSpacing.tapTarget, height: AppSpacing.tapTarget)
                        }
                        .buttonStyle(.plain)
                    }
                } else if !friends.isEmpty && !showEmailSearch {
                    // Friend list picker
                    if isLoadingFriends {
                        ProgressView()
                    } else {
                        ForEach(friends) { friend in
                            Button {
                                selectedFriend = friend
                                HapticManager.selection()
                            } label: {
                                HStack(spacing: AppSpacing.md) {
                                    AvatarView(name: friend.displayName, url: friend.avatarURL, size: AppSpacing.tapTarget)
                                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                        Text(friend.displayName)
                                            .font(.appTitle)
                                        Text(friend.email)
                                            .font(.appCaption)
                                            .foregroundStyle(AppColors.textSecondary)
                                    }
                                    Spacer()
                                }
                                .frame(minHeight: AppSpacing.tapTarget)
                            }
                            .foregroundStyle(AppColors.textPrimary)
                        }
                        Button("Add by email instead") {
                            showEmailSearch = true
                        }
                        .font(.appBody)
                        .foregroundStyle(AppColors.primary)
                    }
                } else {
                    // Email search (no friends yet, or user tapped "Add by email")
                    HStack(spacing: AppSpacing.sm) {
                        XBillTextField(placeholder: "Their email address", text: $emailText, keyboardType: .emailAddress)
                        if isSearching {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Button("Find") { Task { await searchUser() } }
                                .disabled(emailText.isEmpty)
                                .font(.appTitle)
                                .foregroundStyle(AppColors.primary)
                                .frame(minWidth: AppSpacing.tapTarget, minHeight: AppSpacing.tapTarget)
                        }
                    }
                    if let msg = searchError {
                        Text(msg)
                            .font(.appCaption)
                            .foregroundStyle(AppColors.error)
                    }
                    if !friends.isEmpty {
                        Button("Pick from friends") { showEmailSearch = false }
                            .font(.appBody)
                            .foregroundStyle(AppColors.primary)
                    }
                }
            }
        }
    }

    private var directionSection: some View {
        formCard("DIRECTION") {
            XBillSegmentedControl(
                options: [
                    (false, "They owe me"),
                    (true, "I owe them")
                ],
                selection: $iOwe
            )
        }
    }

    private var noteSection: some View {
        formCard("REASON") {
            XBillTextField(placeholder: "What's this for?", text: $description)
        }
    }

    private func formCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(title)
                .font(.appCaptionMedium)
                .tracking(1.08)
                .foregroundStyle(AppColors.textSecondary)
            content()
        }
        .xbillCard()
    }

    // MARK: - Actions

    private func loadFriends() async {
        isLoadingFriends = true
        defer { isLoadingFriends = false }
        do {
            friends = try await FriendService.shared.fetchFriends(userID: currentUserID)
        } catch {
            // Non-fatal — fall back to email search silently
        }
    }

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
