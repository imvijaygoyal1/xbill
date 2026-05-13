//
//  FriendsView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

// MARK: - FriendsView

struct FriendsView: View {
    let currentUserID: UUID?
    var allGroups: [BillGroup] = []

    @State private var ious: [IOU] = []
    @State private var userCache: [UUID: User] = [:]
    @State private var allFriends: [User] = []
    @State private var pendingRequests: [User] = []
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
        guard let currentUserID else { return [] }
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
        guard let currentUserID else { return [:] }
        var balances: [String: Decimal] = [:]
        for iou in ious where !iou.isSettled {
            guard (iou.lenderID == friendID && iou.borrowerID == currentUserID) ||
                  (iou.borrowerID == friendID && iou.lenderID == currentUserID) else { continue }
            let delta: Decimal = iou.lenderID == currentUserID ? iou.amount : -iou.amount
            balances[iou.currency, default: .zero] += delta
        }
        return balances
    }

    private func ious(with friendID: UUID) -> [IOU] {
        guard let currentUserID else { return [] }
        return ious.filter {
            ($0.lenderID == friendID && $0.borrowerID == currentUserID) ||
            ($0.borrowerID == friendID && $0.lenderID == currentUserID)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if isLoading && ious.isEmpty && allFriends.isEmpty {
                        loadingState
                    } else {
                        friendsContent
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
                .toolbarBackground(AppColors.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if isLoading && (!ious.isEmpty || !allFriends.isEmpty) {
                            ProgressView().scaleEffect(0.8)
                        }
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
                if let currentUserID {
                    AddIOUView(currentUserID: currentUserID) { await loadAll() }
                }
            }
            .sheet(isPresented: $showAddFriend) {
                if let currentUserID {
                    AddFriendView(currentUserID: currentUserID) { await loadAll() }
                }
            }
            .navigationDestination(item: $selectedFriendID) { friendID in
                if let currentUserID {
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
    }

    // MARK: - Friend List

    private var loadingState: some View {
        XBillScreenContainer(mode: .fixed) {
            friendsHeader
            Spacer()
            LoadingOverlay(message: "Loading…")
            Spacer()
        }
    }

    private var friendsContent: some View {
        XBillScrollView(spacing: AppSpacing.xl) {
            friendsHeader

            if displayFriendIDs.isEmpty && pendingRequests.isEmpty {
                emptyStateContent
            } else {
                friendSections
            }
        }
        .background(AppColors.background.ignoresSafeArea())
    }

    private var friendsHeader: some View {
        XBillScreenHeader(
            title: "Friends",
            trailingSystemImage: "person.badge.plus",
            trailingAccessibilityLabel: "Add Friend"
        ) {
            showAddFriend = true
        }
        .padding(.horizontal, -AppSpacing.lg)
    }

    @ViewBuilder
    private var friendSections: some View {
        if !pendingRequests.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                XBillSectionHeader("Requests", subtitle: "\(pendingRequests.count) pending")
                ForEach(pendingRequests) { requester in
                    requestRow(requester)
                }
            }
        }

        if !friendIDsWithBalance.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                XBillSectionHeader("Outstanding", subtitle: friendCountText(friendIDsWithBalance.count))
                ForEach(friendIDsWithBalance, id: \.self) { id in
                    Button { selectedFriendID = id } label: { friendRow(friendID: id) }
                        .buttonStyle(.plain)
                }
            }
        }

        if !friendIDsSettled.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                XBillSectionHeader("All Clear", subtitle: friendCountText(friendIDsSettled.count))
                ForEach(friendIDsSettled, id: \.self) { id in
                    Button { selectedFriendID = id } label: { friendRow(friendID: id) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateContent: some View {
        XBillEmptyState(
            icon: "person.2.fill",
            title: "No Friends Yet",
            message: "Add friends to track IOUs or split expenses outside of groups.",
            actionLabel: "Add Friend",
            action: { showAddFriend = true },
            illustration: .friends
        )
        .padding(.top, AppSpacing.md)
    }

    // MARK: - Row Views

    private func requestRow(_ requester: User) -> some View {
        XBillFriendRow(user: requester, detail: "wants to connect") {
            HStack(spacing: AppSpacing.sm) {
                Button {
                    Task { await declineRequest(from: requester) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.appIcon)
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: AppSpacing.tapTarget, height: AppSpacing.tapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Decline request from \(requester.displayName)")

                Button {
                    Task { await acceptRequest(from: requester) }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.appIcon)
                        .foregroundStyle(AppColors.success)
                        .frame(width: AppSpacing.tapTarget, height: AppSpacing.tapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Accept request from \(requester.displayName)")
            }
        }
        .xbillCard()
    }

    private func friendRow(friendID: UUID) -> some View {
        let friend   = userCache[friendID]
        let balances = netBalances(with: friendID)

        let emailDetail: String? = friend.flatMap { $0.email.isEmpty ? nil : $0.email }
        return XBillFriendRow(
            displayName: friend?.displayName ?? "Unknown",
            detail: emailDetail,
            avatarURL: friend?.avatarURL,
            showsChevron: true
        ) {
            VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                if balances.isEmpty {
                    Text("All clear")
                        .font(.appCaptionMedium)
                        .foregroundStyle(AppColors.textSecondary)
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
        .xbillCard()
    }

    private func friendCountText(_ count: Int) -> String {
        "\(count) friend\(count == 1 ? "" : "s")"
    }

    // MARK: - Load

    private func loadAll() async {
        guard let currentUserID else { return }
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
                let profiles = try await friendService.fetchProfiles(ids: missing)
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

}

#Preview("Friends Empty") {
    FriendsView(currentUserID: UUID())
}

#Preview("Friends Empty Dark") {
    FriendsView(currentUserID: UUID())
        .preferredColorScheme(.dark)
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
