import SwiftUI

// MARK: - FriendsView

struct FriendsView: View {
    let currentUserID: UUID

    @State private var ious: [IOU] = []
    @State private var users: [UUID: User] = [:]
    @State private var isLoading = false
    @State private var error: AppError?
    @State private var showAddIOU = false
    @State private var selectedFriendID: UUID?

    private let service = IOUService.shared

    // MARK: - Derived

    /// Unique friend IDs (the "other person" in each IOU)
    private var friendIDs: [UUID] {
        var seen = Set<UUID>()
        return ious
            .map { $0.lenderID == currentUserID ? $0.borrowerID : $0.lenderID }
            .filter { seen.insert($0).inserted }
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

    private func ios(with friendID: UUID) -> [IOU] {
        ious.filter { $0.lenderID == friendID || $0.borrowerID == friendID }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if isLoading && ious.isEmpty {
                        LoadingOverlay(message: "Loading…")
                    } else if friendIDs.isEmpty {
                        EmptyStateView(
                            icon: "person.2.fill",
                            title: "No IOUs Yet",
                            message: "Track money you owe or are owed — outside of groups.",
                            actionLabel: "Add IOU",
                            action: { showAddIOU = true }
                        )
                    } else {
                        friendList
                    }
                }
                .navigationTitle("Friends")
                .navigationBarTitleDisplayMode(.large)
                .toolbarBackground(Color.navBarBg, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .refreshable { await loadIOUs() }
                .task { await loadIOUs() }
                .errorAlert(error: $error)

                if !friendIDs.isEmpty || !isLoading {
                    FABButton { showAddIOU = true }
                        .padding(.bottom, 24)
                        .padding(.trailing, 20)
                }
            }
            .sheet(isPresented: $showAddIOU) {
                AddIOUView(currentUserID: currentUserID) { await loadIOUs() }
            }
            .navigationDestination(item: $selectedFriendID) { friendID in
                FriendDetailView(
                    friendID:      friendID,
                    friend:        users[friendID],
                    currentUserID: currentUserID,
                    allIOUs:       ios(with: friendID)
                ) { await loadIOUs() }
            }
        }
    }

    // MARK: - Friend List

    private var friendList: some View {
        List {
            ForEach(friendIDs, id: \.self) { friendID in
                Button { selectedFriendID = friendID } label: {
                    friendRow(friendID: friendID)
                }
                .listRowBackground(Color.bgCard)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listRowSeparatorTint(Color.separator)
    }

    private func friendRow(friendID: UUID) -> some View {
        let friend = users[friendID]
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

            // Show net balances (one line per currency)
            VStack(alignment: .trailing, spacing: 2) {
                if balances.isEmpty {
                    Text("Settled")
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

    private func loadIOUs() async {
        isLoading = true
        defer { isLoading = false }
        do {
            ious = try await service.fetchIOUs(userID: currentUserID)
            // Fetch profiles for all unique friend IDs
            let ids = Set(ious.flatMap { [$0.lenderID, $0.borrowerID] }).subtracting([currentUserID])
            if !ids.isEmpty {
                let profiles: [User] = try await SupabaseManager.shared.table("profiles")
                    .select()
                    .in("id", values: Array(ids))
                    .execute()
                    .value
                users = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
            }
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
    let onSettled:     () async -> Void

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
