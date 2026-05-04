//
//  FriendsView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

// MARK: - FriendsView

struct FriendsView: View {
    let currentUserID: UUID
    var allGroups: [BillGroup] = []

    @State private var ious: [IOU] = []
    @State private var userCache: [UUID: User] = [:]
    @State private var allFriends: [User] = []
    @State private var pendingRequests: [User] = []
    @State private var contactSuggestions: [User] = []
    @State private var isLoading = false
    @State private var error: AppError?
    @State private var showAddIOU = false
    @State private var showAddFriend = false
    @State private var selectedFriendID: UUID?

    private let iouService    = IOUService.shared
    private let friendService = FriendService.shared

    // MARK: - Derived

    /// Unique IDs of people the current user has IOUs with.
    private var iouFriendIDs: [UUID] {
        var seen = Set<UUID>()
        return ious
            .map { $0.lenderID == currentUserID ? $0.borrowerID : $0.lenderID }
            .filter { seen.insert($0).inserted }
    }

    /// Union of accepted friends + IOU counterparties, deduplicated.
    private var displayFriendIDs: [UUID] {
        var seen = Set<UUID>()
        return (allFriends.map(\.id) + iouFriendIDs).filter { seen.insert($0).inserted }
    }

    /// Friends who have outstanding (unsettled) IOUs — shown in the primary section.
    private var friendIDsWithBalance: [UUID] {
        displayFriendIDs.filter { id in
            ious.contains { iou in
                !iou.isSettled && (iou.lenderID == id || iou.borrowerID == id)
            }
        }
    }

    /// Friends with no outstanding balance.
    private var friendIDsSettled: [UUID] {
        displayFriendIDs.filter { id in !friendIDsWithBalance.contains(id) }
    }

    /// Net balance (from my perspective) with a friend, per currency.
    /// Positive = they owe me, Negative = I owe them.
    private func netBalances(with friendID: UUID) -> [String: Decimal] {
        var balances: [String: Decimal] = [:]
        for iou in ious where !iou.isSettled {
            guard iou.lenderID == friendID || iou.borrowerID == friendID else { continue }
            let delta: Decimal = iou.lenderID == currentUserID ? iou.amount : -iou.amount
            balances[iou.currency, default: .zero] += delta
        }
        return balances
    }

    private func ious(with friendID: UUID) -> [IOU] {
        ious.filter { $0.lenderID == friendID || $0.borrowerID == friendID }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                AppColors.background.ignoresSafeArea()

                Group {
                    if isLoading && ious.isEmpty && allFriends.isEmpty {
                        LoadingOverlay(message: "Loading…")
                    } else if displayFriendIDs.isEmpty && pendingRequests.isEmpty {
                        emptyState
                    } else {
                        friendList
                    }
                }
                .navigationTitle("Friends")
                .navigationBarTitleDisplayMode(.large)
                .toolbarBackground(AppColors.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showAddFriend = true } label: {
                            Image(systemName: "person.badge.plus")
                        }
                        .accessibilityLabel("Add Friend")
                    }
                }
                .refreshable { await loadAll() }
                .task { await loadAll() }
                .errorAlert(error: $error)

                if !displayFriendIDs.isEmpty {
                    FABButton { showAddIOU = true }
                        .padding(.bottom, AppSpacing.floatingActionBottomPadding)
                        .padding(.trailing, AppSpacing.md)
                        .accessibilityLabel("Add IOU")
                }
            }
            .sheet(isPresented: $showAddIOU) {
                AddIOUView(currentUserID: currentUserID) { await loadAll() }
            }
            .sheet(isPresented: $showAddFriend) {
                AddFriendView(currentUserID: currentUserID) { await loadAll() }
            }
            .navigationDestination(item: $selectedFriendID) { friendID in
                FriendDetailView(
                    friendID:      friendID,
                    friend:        userCache[friendID],
                    currentUserID: currentUserID,
                    allIOUs:       ious(with: friendID),
                    allGroups:     allGroups
                ) { await loadAll() }
            }
        }
    }

    // MARK: - Friend List

    private var friendList: some View {
        List {
            if !pendingRequests.isEmpty {
                Section("Requests (\(pendingRequests.count))") {
                    ForEach(pendingRequests) { requester in
                        requestRow(requester)
                    }
                }
            }

            if !friendIDsWithBalance.isEmpty {
                Section("Outstanding") {
                    ForEach(friendIDsWithBalance, id: \.self) { id in
                        Button { selectedFriendID = id } label: { friendRow(friendID: id) }
                            .listRowBackground(Color.bgCard)
                    }
                }
            }

            if !friendIDsSettled.isEmpty {
                Section("All Clear") {
                    ForEach(friendIDsSettled, id: \.self) { id in
                        Button { selectedFriendID = id } label: { friendRow(friendID: id) }
                            .listRowBackground(Color.bgCard)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .listRowSeparatorTint(Color.separator)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 0) {
            EmptyStateView(
                icon: "person.2.fill",
                title: "No Friends Yet",
                message: "Add friends to track IOUs or split expenses outside of groups.",
                actionLabel: "Add Friend",
                action: { showAddFriend = true }
            )

            if !contactSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: XBillSpacing.sm) {
                    Text("FROM YOUR CONTACTS")
                        .font(.xbillUpperLabel)
                        .tracking(1.08)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, XBillSpacing.lg)
                        .padding(.top, XBillSpacing.lg)

                    ForEach(contactSuggestions) { user in
                        HStack(spacing: XBillSpacing.md) {
                            AvatarView(name: user.displayName, url: user.avatarURL, size: XBillIcon.avatarSm)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName).font(.xbillBodyMedium)
                                Text(user.email).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Add") { Task { await quickAdd(user) } }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                        .padding(.horizontal, XBillSpacing.lg)
                        .padding(.vertical, XBillSpacing.xs)
                    }
                }
            }
        }
    }

    // MARK: - Row Views

    private func requestRow(_ requester: User) -> some View {
        HStack(spacing: XBillSpacing.md) {
            AvatarView(name: requester.displayName, url: requester.avatarURL, size: XBillIcon.avatarSm)

            VStack(alignment: .leading, spacing: 2) {
                Text(requester.displayName)
                    .font(.xbillBodyMedium)
                    .foregroundStyle(Color.textPrimary)
                Text("wants to connect")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: XBillSpacing.sm) {
                Button {
                    Task { await declineRequest(from: requester) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Decline request from \(requester.displayName)")

                Button {
                    Task { await acceptRequest(from: requester) }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.brandPrimary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Accept request from \(requester.displayName)")
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.bgCard)
    }

    private func friendRow(friendID: UUID) -> some View {
        let friend   = userCache[friendID]
        let balances = netBalances(with: friendID)

        return HStack(spacing: XBillSpacing.md) {
            AvatarView(name: friend?.displayName ?? "?", url: friend?.avatarURL, size: XBillIcon.avatarSm)

            VStack(alignment: .leading, spacing: 2) {
                Text(friend?.displayName ?? "Unknown")
                    .font(.xbillBodyMedium)
                    .foregroundStyle(Color.textPrimary)
                if let email = friend?.email {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if balances.isEmpty {
                    Text("All clear")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(balances.keys.sorted(), id: \.self) { currency in
                        let net = balances[currency]!
                        AmountBadge(
                            amount: abs(net),
                            direction: net > .zero ? .positive : .negative,
                            currency: currency
                        )
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: - Load

    private func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let iousFetch     = iouService.fetchIOUs(userID: currentUserID)
            async let friendsFetch  = friendService.fetchFriends(userID: currentUserID)
            async let pendingFetch  = friendService.fetchPendingReceived(userID: currentUserID)

            let (fetchedIOUs, fetchedFriends, fetchedPending) = try await (iousFetch, friendsFetch, pendingFetch)
            ious           = fetchedIOUs
            allFriends     = fetchedFriends
            pendingRequests = fetchedPending

            // Build profile cache from all unique IDs
            var allIDs = Set(fetchedFriends.map(\.id))
                .union(fetchedPending.map(\.id))
                .union(fetchedIOUs.flatMap { [$0.lenderID, $0.borrowerID] })
            allIDs.remove(currentUserID)

            // Seed from already-fetched profiles
            for user in fetchedFriends + fetchedPending { userCache[user.id] = user }

            // Fetch any remaining (IOU counterparties not yet in cache)
            let missing = allIDs.subtracting(userCache.keys)
            if !missing.isEmpty {
                let profiles: [User] = try await SupabaseManager.shared.table("profiles")
                    .select()
                    .in("id", values: Array(missing))
                    .execute()
                    .value
                for user in profiles { userCache[user.id] = user }
            }
        } catch {
            self.error = AppError.from(error)
        }
    }

    // MARK: - Friend Request Actions

    private func acceptRequest(from requester: User) async {
        do {
            try await friendService.acceptRequest(from: requester.id)
            HapticManager.success()
            await loadAll()
        } catch {
            self.error = AppError.from(error)
        }
    }

    private func declineRequest(from requester: User) async {
        do {
            try await friendService.declineRequest(from: requester.id)
            HapticManager.selection()
            await loadAll()
        } catch {
            self.error = AppError.from(error)
        }
    }

    private func quickAdd(_ user: User) async {
        do {
            try await friendService.sendFriendRequest(to: user.id)
            HapticManager.success()
            contactSuggestions.removeAll { $0.id == user.id }
            await loadAll()
        } catch {
            self.error = AppError.from(error)
        }
    }
}

// MARK: - FriendDetailView

struct FriendDetailView: View {
    let friendID:      UUID
    let friend:        User?
    let currentUserID: UUID
    let allIOUs:       [IOU]
    var allGroups:     [BillGroup] = []
    let onSettled:     () async -> Void

    @State private var mutualGroups: [BillGroup] = []
    @State private var showAddIOU = false
    @State private var isSettling = false
    @State private var error: AppError?
    @Environment(\.dismiss) private var dismiss

    private var unsettledIOUs: [IOU] { allIOUs.filter { !$0.isSettled } }
    private var settledIOUs:   [IOU] { allIOUs.filter { $0.isSettled } }

    var body: some View {
        List {
            if !unsettledIOUs.isEmpty {
                Section("Outstanding") {
                    ForEach(unsettledIOUs) { iou in
                        iouRow(iou)
                    }
                }

                Section {
                    XBillButton(title: isSettling ? "Settling…" : "Settle All with \(friend?.displayName ?? "Friend")", style: .primary) {
                        Task { await settleAll() }
                    }
                    .disabled(isSettling)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if !settledIOUs.isEmpty {
                Section("Settled") {
                    ForEach(settledIOUs) { iou in
                        iouRow(iou)
                    }
                }
            }

            if !mutualGroups.isEmpty {
                Section("Shared Groups") {
                    ForEach(mutualGroups) { group in
                        HStack(spacing: XBillSpacing.md) {
                            Text(group.emoji)
                                .font(.title3)
                                .frame(width: 36, height: 36)
                                .background(Color.bgTertiary)
                                .clipShape(Circle())
                            Text(group.name)
                                .font(.xbillBodyMedium)
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Text(group.currency)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if allIOUs.isEmpty {
                EmptyStateView(
                    icon: "checkmark.circle.fill",
                    title: "No IOUs",
                    message: "No money tracked with this person yet."
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(friend?.displayName ?? "Friend")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddIOU = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddIOU) {
            AddIOUView(currentUserID: currentUserID, preselectedFriendID: friendID, preselectedFriend: friend) {
                await onSettled()
            }
        }
        .errorAlert(error: $error)
        .task { await loadMutualGroups() }
    }

    private func loadMutualGroups() async {
        guard !allGroups.isEmpty else { return }
        do {
            let mutualIDs = try await FriendService.shared.fetchMutualGroupIDs(
                currentUserID: currentUserID, friendID: friendID)
            mutualGroups = allGroups.filter { mutualIDs.contains($0.id) }
        } catch {
            // Non-fatal — mutual groups section stays empty
        }
    }

    private func iouRow(_ iou: IOU) -> some View {
        let iOwe = iou.borrowerID == currentUserID
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let desc = iou.description, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundStyle(Color.textPrimary)
                }
                Text(iOwe ? "You owe" : "They owe you")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(iou.createdAt.shortFormatted)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            AmountBadge(
                amount: iou.amount,
                direction: iou.isSettled ? .settled : (iOwe ? .negative : .positive),
                currency: iou.currency
            )
        }
        .padding(.vertical, 2)
    }

    private func settleAll() async {
        isSettling = true
        defer { isSettling = false }
        do {
            try await IOUService.shared.settleAllIOUs(with: friendID, currentUserID: currentUserID)
            HapticManager.success()
            await onSettled()
            dismiss()
        } catch {
            self.error = AppError.from(error)
        }
    }
}
