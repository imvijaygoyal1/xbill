import SwiftUI

struct JoinGroupView: View {
    let token: String
    var onJoined: () async -> Void

    @State private var group: BillGroup?
    @State private var isLoading = true
    @State private var isJoining = false
    @State private var error: AppError?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: XBillSpacing.xl) {
                Spacer()

                if isLoading {
                    ProgressView("Loading invite…")
                } else if let group {
                    groupCard(group)
                    joinButton(group)
                } else {
                    EmptyStateView(
                        icon: "link.badge.xmark",
                        title: "Invalid Invite",
                        message: error?.localizedDescription ?? "This invite link is invalid or has expired."
                    )
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Join Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await loadInvite() }
            .errorAlert(error: $error)
        }
    }

    // MARK: - Subviews

    private func groupCard(_ group: BillGroup) -> some View {
        VStack(spacing: XBillSpacing.md) {
            Text(group.emoji)
                .font(.system(size: 64))

            Text("You've been invited to join")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(group.name)
                .font(.title.bold())
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)

            Text(group.currency)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, XBillSpacing.sm)
                .padding(.vertical, 4)
                .background(Color.bgSecondary)
                .clipShape(Capsule())
        }
        .padding(XBillSpacing.xl)
        .frame(maxWidth: .infinity)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XBillRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XBillRadius.lg)
                .stroke(Color.separator, lineWidth: 0.5)
        )
    }

    private func joinButton(_ group: BillGroup) -> some View {
        XBillButton(title: isJoining ? "Joining…" : "Join \(group.name)", style: .primary) {
            Task { await joinGroup() }
        }
        .disabled(isJoining)
    }

    // MARK: - Actions

    private func loadInvite() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let invite = try await GroupService.shared.fetchInvite(token: token)
            group = try await GroupService.shared.fetchGroup(id: invite.groupID)
        } catch {
            self.error = AppError.from(error)
        }
    }

    private func joinGroup() async {
        isJoining = true
        defer { isJoining = false }
        do {
            _ = try await GroupService.shared.joinGroupViaInvite(token: token)
            HapticManager.success()
            await onJoined()
            dismiss()
        } catch {
            self.error = AppError.from(error)
        }
    }
}
