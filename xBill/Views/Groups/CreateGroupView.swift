//
//  CreateGroupView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct CreateGroupView: View {
    let onCreated: (BillGroup) async -> Void

    @State private var name: String = ""
    @State private var selectedEmoji: String = "💸"
    @State private var currency: String = "USD"
    @State private var inviteEmail: String = ""
    @State private var isLoading: Bool = false
    @State private var error: AppError?

    @Environment(\.dismiss) private var dismiss

    private let emojis = [
        "💸", "💰", "🍕", "🍺", "🏠", "✈️", "🎮", "🎬", "🛒", "🏋️",
        "🎵", "🚗", "💊", "📚", "🌮", "🍣", "⚽", "🎯", "🎁", "🧳"
    ]

    private let currencies = ExchangeRateService.commonCurrencies

    var canCreate: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return false }
        let trimmedEmail = inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEmail.isEmpty { return isValidEmail(trimmedEmail) }
        return true
    }

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    var body: some View {
        NavigationStack {
            XBillScreenContainer(
                horizontalPadding: AppSpacing.lg,
                bottomPadding: AppSpacing.floatingActionBottomPadding
            ) {
                        XBillPageHeader(
                            title: "New Group",
                            subtitle: "Name your group, pick a visual, and choose a default currency.",
                            showsBackButton: true,
                            backAction: { dismiss() }
                        )
                        .padding(.horizontal, -AppSpacing.lg)

                        formSection("Group Name") {
                            XBillTextField(placeholder: "e.g. Weekend Trip", text: $name)
                                .autocorrectionDisabled()
                        }

                        formSection("Icon") {
                            XBillIconPickerGrid(icons: emojis, selectedIcon: $selectedEmoji)
                        }

                        formSection("Currency") {
                            Picker("Currency", selection: $currency) {
                                ForEach(currencies, id: \.self) { code in
                                    Text(code).tag(code)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(AppColors.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: AppSpacing.tapTarget)
                        }

                        formSection("Invite by Email") {
                            XBillTextField(placeholder: "friend@email.com", text: $inviteEmail, keyboardType: .emailAddress)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            Text("You can also invite people after the group is created.")
                                .font(.appCaption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
            } stickyBottom: {
                XBillPrimaryButton(
                    title: "Create Group",
                    icon: "checkmark",
                    isLoading: isLoading,
                    isDisabled: !canCreate
                ) {
                    Task { await create() }
                }
                .accessibilityIdentifier("xBill.createGroup.submitButton")
                .padding(AppSpacing.md)
                .background(.ultraThinMaterial)
            }
            .navigationBarBackButtonHidden()
            .toolbar(.hidden, for: .navigationBar)
        }
        .errorAlert(error: $error)
    }

    private func formSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(title.uppercased())
                .font(.appCaptionMedium)
                .tracking(1.08)
                .foregroundStyle(AppColors.textSecondary)
            content()
        }
        .xbillCard()
    }

    // MARK: - Action

    private func create() async {
        guard let userID = await AuthService.shared.currentUserID else {
            error = .unauthenticated
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let profile = try? await AuthService.shared.currentUser()
            let group = try await GroupService.shared.createGroup(
                name: name.trimmingCharacters(in: .whitespaces),
                emoji: selectedEmoji,
                currency: currency,
                createdBy: userID
            )
            let trimmedEmail = inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedEmail.isEmpty {
                try? await GroupService.shared.inviteMembers(
                    emails: [trimmedEmail],
                    groupName: group.name,
                    groupEmoji: group.emoji,
                    inviterName: profile?.displayName ?? "Someone"
                )
            }
            await onCreated(group)
            dismiss()
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.error = AppError.from(error)
        }
    }
}

#Preview {
    CreateGroupView { _ in }
}
