//
//  JoinGroupView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct JoinGroupView: View {
    let token: String
    var onJoined: () async -> Void

    @State private var preview: InvitePreview?
    @State private var isLoading = true
    @State private var isJoining = false
    @State private var error: AppError?
    /// INV-01: a preview that fails to load is NOT a dead end. The join itself runs through a
    /// SECURITY DEFINER RPC that validates the token server-side, so the only honest thing the
    /// preview failing tells us is that we cannot show the group's name — not that the invite is
    /// bad. Presenting "Invalid Invite" on a preview failure is what made every invite look
    /// broken. The server decides validity, on join.
    @State private var previewUnavailable = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: XBillSpacing.xl) {
                Spacer()

                if isLoading {
                    ProgressView("Loading invite…")
                } else if let preview {
                    groupCard(preview)
                    joinButton(title: "Join \(preview.name)")
                } else if previewUnavailable {
                    unnamedInviteCard
                    joinButton(title: "Join Group")
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

    private func groupCard(_ preview: InvitePreview) -> some View {
        VStack(spacing: XBillSpacing.md) {
            Text(preview.displayEmoji)
                .font(.system(size: 64))

            Text("You've been invited to join")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(preview.name)
                .font(.title.bold())
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)

            Text("\(preview.memberSummary) · \(preview.currency)")
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

    /// Shown when the preview could not be fetched — on an older backend, or offline. The invite
    /// may be perfectly good, so the action stays available and the server adjudicates.
    private var unnamedInviteCard: some View {
        VStack(spacing: XBillSpacing.md) {
            Text("👥").font(.system(size: 64))
            Text("You've been invited to join a group")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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

    private func joinButton(title: String) -> some View {
        XBillButton(title: isJoining ? "Joining…" : title, style: .primary) {
            Task { await joinGroup() }
        }
        .disabled(isJoining)
        .accessibilityIdentifier("xBill.joinGroup.joinButton")
    }

    // MARK: - Actions

    private func loadInvite() async {
        isLoading = true
        defer { isLoading = false }
        do {
            preview = try await GroupService.shared.fetchInvitePreview(token: token)
        } catch {
            // Deliberately not surfaced as an error: see `previewUnavailable`. The token is
            // validated on join, by the server, which is the only place that can judge it.
            previewUnavailable = true
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
