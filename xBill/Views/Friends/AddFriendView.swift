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

    private var addFriendURL: URL {
        URL(string: "xbill://add/\(currentUserID.uuidString)")!
    }

    var body: some View {
        NavigationStack {
            XBillScreenContainer(contentSpacing: AppSpacing.xl) {
                XBillDetailHeader(
                    title: "Add Friend",
                    subtitle: "Find people by email, QR link, or contacts.",
                    backAction: { dismiss() }
                )
                .padding(.horizontal, -AppSpacing.lg)

                XBillIllustrationCard {
                    XBillFriendsIllustration(size: 210)
                }

                searchSection

                if let user = preloadedUser {
                    preloadedSection(user)
                }

                if !searchResults.isEmpty {
                    searchResultsSection
                } else if !searchText.isEmpty && !isSearching {
                    noResultsSection
                }

                if !contactSuggestions.isEmpty {
                    suggestionsSection
                }
            }
            .navigationBarBackButtonHidden()
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(AppColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            XBillSectionHeader("Suggested")
            userRow(user)
        }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            XBillSectionHeader("Find People")

            XBillSearchBar(placeholder: "Name or email", text: $searchText, accessibilityLabel: "Search friends")
                .onChange(of: searchText) { _, new in scheduleSearch(query: new) }

            if isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AppSpacing.tapTarget)
                    .xbillCard()
            }

            actionRows
        }
    }

    private var actionRows: some View {
        VStack(spacing: AppSpacing.md) {
            Button {
                showContactPicker = true
            } label: {
                XBillActionRow(
                    icon: "person.crop.circle.badge.plus",
                    title: "Import from Contacts",
                    subtitle: "Find people already using xBill"
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Import from Contacts")

            ShareLink(
                item: addFriendURL,
                subject: Text("Add me on xBill"),
                message: Text("Tap to add me as a friend on xBill.")
            ) {
                XBillActionRow(
                    icon: "qrcode",
                    title: "Share QR Link",
                    subtitle: "Let friends add you directly"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            XBillSectionHeader("From Your Contacts", subtitle: "\(contactSuggestions.count) found")
            ForEach(contactSuggestions) { user in
                userRow(user)
            }
        }
    }

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            XBillSectionHeader("Search Results", subtitle: "\(searchResults.count) found")
            ForEach(searchResults) { user in
                userRow(user)
            }
        }
    }

    private var noResultsSection: some View {
        VStack(spacing: AppSpacing.md) {
            XBillEmptyState(
                icon: "magnifyingglass",
                title: "No matching friends",
                message: "Try another name or email.",
                showsIllustration: false
            )
            .padding(AppSpacing.lg)
            .xbillCard()

            ShareLink(
                item: XBillURLs.appInvite,
                subject: Text("Join me on xBill"),
                message: Text("I use xBill to split bills and track IOUs. Join me!")
            ) {
                XBillActionRow(
                    icon: "envelope.badge",
                    title: "Invite to xBill",
                    subtitle: "Send an app invite instead"
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - User Row

    private func userRow(_ user: User) -> some View {
        XBillFriendRow(user: user) {
            addButton(for: user)
        }
        .xbillCard()
        .accessibilityLabel("\(user.displayName), \(user.email)")
    }

    @ViewBuilder
    private func addButton(for user: User) -> some View {
        if sentRequestIDs.contains(user.id) {
            XBillPillButton(title: "Pending", style: .secondary, isDisabled: true) {}
        } else {
            XBillPillButton(title: "Add") {
                Task { await sendRequest(to: user) }
            }
            .accessibilityLabel("Add \(user.displayName)")
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

#Preview("Add Friend") {
    AddFriendView(currentUserID: UUID()) {}
}

#Preview("Add Friend Dark") {
    AddFriendView(currentUserID: UUID()) {}
        .preferredColorScheme(.dark)
}
