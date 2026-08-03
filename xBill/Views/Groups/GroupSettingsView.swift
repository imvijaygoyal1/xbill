//
//  GroupSettingsView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  Extracted from `GroupDetailView.swift`, which held five top-level types in 1,197 lines and had
//  already been split into `baseContent`/`lifecycleContent`/`decoratedContent` — not for clarity
//  but to escape a Swift type-checker timeout. A file that large is also why logic tends to live
//  in view bodies where no unit test can reach it.
//

import SwiftUI

struct GroupSettingsView: View {
    @Bindable var vm: GroupViewModel
    let currentUserID: UUID
    let onChanged: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var emoji: String
    @State private var currency: String
    @State private var showInvite = false
    @State private var showInviteLink = false
    @State private var memberToRemove: User?

    private let icons = ["🏠", "✈️", "🍽️", "🎉", "🏖️", "🏢", "🎮", "🚗", "🎵", "💼"]

    init(vm: GroupViewModel, currentUserID: UUID, onChanged: @escaping () async -> Void) {
        self.vm = vm
        self.currentUserID = currentUserID
        self.onChanged = onChanged
        _name = State(initialValue: vm.group.name)
        _emoji = State(initialValue: vm.group.emoji)
        _currency = State(initialValue: vm.group.currency)
    }

    private var isOwner: Bool {
        vm.group.createdBy == currentUserID
    }

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !vm.isLoading else { return false }
        let currencyChanged = vm.canChangeCurrency && currency != vm.group.currency
        return trimmed != vm.group.name || emoji != vm.group.emoji || currencyChanged
    }

    var body: some View {
        NavigationStack {
            XBillScreenContainer(
                horizontalPadding: AppSpacing.lg,
                contentSpacing: AppSpacing.xl,
                bottomPadding: AppSpacing.xl
            ) {
                XBillPageHeader(
                    title: "Manage Group",
                    subtitle: "Edit details, invites, and members.",
                    showsBackButton: true,
                    backAction: { dismiss() }
                )
                .padding(.horizontal, -AppSpacing.lg)

                detailsSection
                inviteSection
                membersSection
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showInvite) {
                InviteMembersView(group: vm.group) {
                    await vm.load()
                    await onChanged()
                }
            }
            .sheet(isPresented: $showInviteLink) {
                GroupInviteView(group: vm.group, currentUserID: currentUserID)
            }
            .confirmationDialog(
                "Remove Member?",
                isPresented: Binding(
                    get: { memberToRemove != nil },
                    set: { if !$0 { memberToRemove = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    guard let member = memberToRemove else { return }
                    Task {
                        await vm.removeMember(userID: member.id)
                        if vm.errorAlert == nil {
                            await onChanged()
                            memberToRemove = nil
                        }
                    }
                }
                Button("Cancel", role: .cancel) { memberToRemove = nil }
            } message: {
                if let memberToRemove {
                    Text("\(memberToRemove.displayName) will lose access to this group. Their historical expenses and splits stay visible.")
                }
            }
        }
        .errorAlert(item: $vm.errorAlert)
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            XBillSectionHeader("Details")
            XBillFormSection {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    XBillTextField(placeholder: "Group name", text: $name)
                        .accessibilityLabel("Group name")
                        .accessibilityIdentifier("xBill.groupSettings.nameField")

                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Icon")
                            .font(.appCaptionMedium)
                            .foregroundStyle(AppColors.textSecondary)
                        XBillIconPickerGrid(icons: icons, selectedIcon: $emoji)
                    }

                    HStack(spacing: AppSpacing.md) {
                        Text("Currency")
                            .font(.appBody)
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Picker("Currency", selection: $currency) {
                            ForEach(ExchangeRateService.commonCurrencies, id: \.self) { code in
                                Text(code).tag(code)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(AppColors.primary)
                        .disabled(!vm.canChangeCurrency)
                        .accessibilityIdentifier("xBill.groupSettings.currencyPicker")
                    }
                    if !vm.canChangeCurrency {
                        Text("Currency is locked after the first expense to keep historical amounts accurate.")
                            .font(.appCaption)
                            .foregroundStyle(AppColors.textSecondary)
                            .accessibilityIdentifier("xBill.groupSettings.currencyLockedMessage")
                    }

                    XBillPrimaryButton(
                        title: "Save Changes",
                        icon: "checkmark",
                        isLoading: vm.isLoading,
                        isDisabled: !canSave
                    ) {
                        Task {
                            await vm.updateGroupDetails(name: name, emoji: emoji, currency: currency)
                            name = vm.group.name
                            emoji = vm.group.emoji
                            currency = vm.group.currency
                            await onChanged()
                        }
                    }
                    .accessibilityIdentifier("xBill.groupSettings.saveButton")
                }
            }
        }
    }

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            XBillSectionHeader("Invites")
            XBillActionCard(
                icon: "envelope.fill",
                title: "Invite by Email",
                subtitle: "Send a group invite to a member."
            ) {
                showInvite = true
            }
            .accessibilityIdentifier("xBill.groupSettings.inviteEmailButton")
            XBillActionCard(
                icon: "qrcode",
                title: "Invite Link",
                subtitle: "Share a reusable link or QR code."
            ) {
                showInviteLink = true
            }
            .accessibilityIdentifier("xBill.groupSettings.inviteLinkButton")
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            XBillSectionHeader("Members", subtitle: "\(vm.activeMembers.count) active · \(vm.members.count) historical")
            XBillFormSection {
                VStack(spacing: 0) {
                    ForEach(Array(vm.members.enumerated()), id: \.element.id) { index, member in
                        memberRow(member)
                        if index < vm.members.count - 1 {
                            Divider()
                                .overlay(AppColors.border)
                        }
                    }

                    if vm.members.isEmpty {
                        Text("Members will appear after the group finishes loading.")
                            .font(.appCaption)
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if !isOwner {
                Text("Only the group owner can remove members.")
                    .font(.appCaption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private func memberRow(_ member: User) -> some View {
        HStack(spacing: AppSpacing.md) {
            AvatarView(name: member.displayName, url: member.avatarURL, size: XBillIcon.avatarSm)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(member.displayName)
                    .font(.appBody)
                    .foregroundStyle(AppColors.textPrimary)
                if !member.email.isEmpty {
                    Text(member.email)
                        .font(.appCaption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()

            if vm.group.createdBy == member.id {
                Text("Owner")
                    .font(.appCaptionMedium)
                    .foregroundStyle(AppColors.primary)
                    .padding(.horizontal, AppSpacing.sm)
                    .frame(minHeight: 28)
                    .background(AppColors.surfaceSoft)
                    .clipShape(Capsule())
            } else if isOwner {
                Button(role: .destructive) {
                    memberToRemove = member
                } label: {
                    Image(systemName: member.isActive ? "person.crop.circle.badge.minus" : "clock.badge")
                        .font(.appTitle)
                        .foregroundStyle(member.isActive ? AppColors.error : AppColors.textTertiary)
                        .frame(width: AppSpacing.tapTarget, height: AppSpacing.tapTarget)
                }
                .buttonStyle(.plain)
                .disabled(!member.isActive)
                .accessibilityLabel("Remove \(member.displayName)")
            }
            if !member.isActive {
                Text("Inactive")
                    .font(.appCaptionMedium)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, AppSpacing.sm)
                    .frame(minHeight: 28)
                    .background(AppColors.surfaceSoft)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, AppSpacing.sm)
    }
}

// MARK: - Filter Chip
