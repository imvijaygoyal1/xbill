//
//  AddFriendView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

// MARK: - AddFriendView

struct AddFriendView: View {
    let currentUserID: UUID
    /// Optional pre-loaded user (e.g. from QR code deep link).
    var preloadedUser: User? = nil
    let onAdded: () async -> Void

    @State private var searchText:     String = ""
    @State private var searchResults:  [User] = []
    @State private var isSearching     = false
    @State private var searchTask:     Task<Void, Never>?

    @State private var contactSuggestions: [User] = []
    @State private var showContactPicker   = false

    @State private var sentRequestIDs: Set<UUID> = []
    @State private var error: AppError?

    @Environment(\.dismiss) private var dismiss

    private let service = FriendService.shared

    var body: some View {
        NavigationStack {
            List {
                if let user = preloadedUser {
                    preloadedSection(user)
                }

                searchSection

                if !contactSuggestions.isEmpty {
                    suggestionsSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.bgSecondary.ignoresSafeArea())
            .navigationTitle("Add Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.navBarBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .errorAlert(error: $error)
            .sheet(isPresented: $showContactPicker) {
                ContactPickerRepresentable { emails in
                    showContactPicker = false
                    Task { await lookupContactEmails(emails) }
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Sections

    private func preloadedSection(_ user: User) -> some View {
        Section("Suggested") {
            userRow(user)
        }
    }

    private var searchSection: some View {
        Section {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Name or email", text: $searchText)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .onChange(of: searchText) { _, new in scheduleSearch(query: new) }
                if isSearching {
                    ProgressView().scaleEffect(0.8)
                }
            }

            if !searchResults.isEmpty {
                ForEach(searchResults) { user in
                    userRow(user)
                }
            } else if !searchText.isEmpty && !isSearching {
                inviteRow
            }

            Button {
                showContactPicker = true
            } label: {
                Label("Import from Contacts", systemImage: "person.crop.circle.badge.plus")
                    .foregroundStyle(Color.brandPrimary)
            }
        } header: {
            Text("Find people")
        }
    }

    private var suggestionsSection: some View {
        Section("From your contacts on xBill") {
            ForEach(contactSuggestions) { user in
                userRow(user)
            }
        }
    }

    private var inviteRow: some View {
        ShareLink(
            item: XBillURLs.appInvite,
            subject: Text("Join me on xBill"),
            message: Text("I use xBill to split bills and track IOUs. Join me!")
        ) {
            Label("Invite \"\(searchText)\" to xBill", systemImage: "envelope.badge.plus")
                .foregroundStyle(Color.brandPrimary)
        }
    }

    // MARK: - User Row

    private func userRow(_ user: User) -> some View {
        HStack(spacing: XBillSpacing.md) {
            AvatarView(name: user.displayName, url: user.avatarURL, size: XBillIcon.avatarSm)

            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.xbillBodyMedium)
                    .foregroundStyle(Color.textPrimary)
                Text(user.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            addButton(for: user)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(user.displayName), \(user.email)")
    }

    @ViewBuilder
    private func addButton(for user: User) -> some View {
        if sentRequestIDs.contains(user.id) {
            Text("Pending")
                .font(.xbillCaption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.bgTertiary)
                .clipShape(Capsule())
        } else {
            Button {
                Task { await sendRequest(to: user) }
            } label: {
                Text("Add")
                    .font(.xbillCaption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.brandPrimary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    private func scheduleSearch(query: String) {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await runSearch(query: query)
        }
    }

    private func runSearch(query: String) async {
        isSearching = true
        defer { isSearching = false }
        do {
            searchResults = try await service.searchProfiles(query: query)
        } catch {
            self.error = AppError.from(error)
        }
    }

    private func lookupContactEmails(_ emails: [String]) async {
        do {
            let found = try await service.lookupByContactEmails(emails)
            // Merge, deduplicating by ID
            var existing = Set(contactSuggestions.map(\.id))
            for user in found where !existing.contains(user.id) {
                contactSuggestions.append(user)
                existing.insert(user.id)
            }
        } catch {
            self.error = AppError.from(error)
        }
    }

    private func sendRequest(to user: User) async {
        do {
            try await service.sendFriendRequest(to: user.id)
            sentRequestIDs.insert(user.id)
            HapticManager.success()
            await onAdded()
        } catch {
            self.error = AppError.from(error)
        }
    }
}
