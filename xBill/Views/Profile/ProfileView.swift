//
//  ProfileView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI
import UIKit
import PhotosUI
import UserNotifications

// MARK: - PhotoPickerView

private struct PhotoPickerView: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPickerView

        init(_ parent: PhotoPickerView) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { [weak self] image, _ in
                guard let self, let uiImage = image as? UIImage else { return }
                Task { @MainActor [self] in
                    self.parent.selectedImage = uiImage
                }
            }
        }
    }
}

// MARK: - ProfileView

struct ProfileView: View {
    @Bindable var vm: ProfileViewModel
    var onSignOut: (() -> Void)? = nil
    var loadsOnAppear = true

    @State private var isEditing = false
    @State private var showSignOutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var selectedAvatar: UIImage? = nil
    @State private var showAvatarPicker = false
    @State private var showPrivacy = false
    @State private var showTerms = false
    @State private var showMyQR = false

    @State private var prefPushExpense = false
    @State private var prefPushSettlement = false
    @State private var prefPushComment = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isRequestingNotifications = false
    @State private var lockService = AppLockService.shared

    var body: some View {
        NavigationStack {
            XBillScreenBackground {
                ScrollView(.vertical, showsIndicators: true) {
                    profileContent
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.bottom, scrollBottomPadding)
                }
                .refreshable { await vm.load() }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(AppColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task {
                if loadsOnAppear {
                    await vm.load()
                }
                await refreshNotificationStatus()
                loadNotificationPreferences()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                Task {
                    await refreshNotificationStatus()
                    loadNotificationPreferences()
                }
            }
            .sheet(isPresented: $isEditing) {
                editSheet
            }
            .sheet(isPresented: $showMyQR) {
                if let userID = vm.user?.id {
                    MyQRCodeView(userID: userID, displayName: vm.user?.displayName ?? "")
                }
            }
            .safariSheet(isPresented: $showPrivacy, url: XBillURLs.privacyPolicy)
            .sheet(isPresented: $showTerms) {
                TermsOfServiceView()
            }
            .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    if let onSignOut {
                        onSignOut()
                    } else {
                        Task { await vm.signOut() }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Delete your account?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete account", role: .destructive) {
                    Task { await vm.deleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes your profile, avatar, payment handles, and notification tokens. Shared expense records stay in groups so other members keep their history.")
            }
        }
        .errorAlert(item: $vm.errorAlert)
    }

    private var profileContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            XBillScreenHeader(title: "Profile")
                .padding(.horizontal, -AppSpacing.lg)

            XBillProfileCard(
                user: vm.user,
                initials: vm.initials,
                onEdit: { isEditing = true },
                onQR: { showMyQR = true }
            )

            profileSection("Your Stats") {
                XBillStatsCard(items: [
                    .init(title: "Groups", value: "\(vm.totalGroupsCount)"),
                    .init(title: "Expenses", value: "\(vm.totalExpensesCount)"),
                    .init(title: "Total Paid", value: vm.lifetimePaid.formatted(currencyCode: vm.primaryCurrency))
                ])
                .redacted(reason: vm.isLoading ? .placeholder : [])
            }

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    XBillSectionHeader("Payment Handles")
                    Spacer()
                    if hasUnsavedHandles {
                        Button("Save") {
                            Task { await vm.saveProfile(avatarImage: nil) }
                        }
                        .font(.appCaption)
                        .foregroundStyle(canSaveHandles ? AppColors.primary : AppColors.textTertiary)
                        .disabled(!canSaveHandles)
                    }
                }
                XBillFormSection {
                    VStack(spacing: AppSpacing.lg) {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        XBillPaymentHandleRow(
                            providerName: "Venmo",
                            systemImage: "dollarsign.circle.fill",
                            placeholder: "@venmo-handle",
                            text: $vm.venmoHandle
                        )
                        .accessibilityIdentifier("xBill.profile.venmoField")
                        validationText(venmoValidationMessage)
                        }

                        Divider()
                            .overlay(AppColors.border)

                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        XBillPaymentHandleRow(
                            providerName: "PayPal",
                            systemImage: "p.circle.fill",
                            placeholder: "paypalme-handle",
                            text: $vm.paypalHandle,
                            keyboardType: .default
                        )
                        .accessibilityIdentifier("xBill.profile.paypalField")
                        validationText(paypalValidationMessage)
                        }
                    }
                }
            }

            profileSection("Notifications") {
                notificationsSection
            }

            profileSection("Security") {
                XBillFormSection {
                    XBillSettingsRow(
                        icon: lockService.lockIconName,
                        title: "Require Face ID / Passcode"
                    ) {
                        Toggle("", isOn: $lockService.isEnabled)
                            .labelsHidden()
                            .tint(AppColors.primary)
                    }
                }
            }

            profileSection("Account") {
                XBillFormSection {
                    VStack(spacing: AppSpacing.sm) {
                        XBillSettingsRow(
                            icon: "rectangle.portrait.and.arrow.right",
                            title: "Sign Out",
                            isDestructive: true,
                            action: { showSignOutConfirm = true }
                        )
                        .accessibilityIdentifier("xBill.profile.signOutButton")

                        Divider()
                            .overlay(AppColors.border)

                        XBillSettingsRow(
                            icon: "trash",
                            title: "Delete account",
                            subtitle: "Permanently remove your profile.",
                            isDestructive: true,
                            action: { showDeleteConfirm = true }
                        )
                        .accessibilityIdentifier("xBill.profile.deleteAccountButton")
                    }
                }
            }

            footer
        }
    }

    private var hasUnsavedHandles: Bool {
        vm.venmoHandle != (vm.user?.venmoHandle ?? "") ||
        vm.paypalHandle != (vm.user?.paypalHandle ?? "")
    }

    private var canSaveHandles: Bool {
        hasUnsavedHandles && !vm.isLoading && venmoValidationMessage == nil && paypalValidationMessage == nil
    }

    private var venmoValidationMessage: String? {
        let value = vm.venmoHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard value.hasPrefix("@") else { return "Venmo handles should start with @." }
        let handle = value.dropFirst()
        guard handle.count >= 2 else { return "Enter at least 2 characters after @." }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return handle.unicodeScalars.allSatisfy { allowed.contains($0) } ? nil : "Use letters, numbers, dot, dash, or underscore."
    }

    private var paypalValidationMessage: String? {
        let value = vm.paypalHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let handle = value.hasPrefix("@") ? value.dropFirst() : Substring(value)
        guard handle.count >= 2 else { return "Enter at least 2 characters." }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return handle.unicodeScalars.allSatisfy { allowed.contains($0) } ? nil : "Use your PayPal.me handle: letters, numbers, dot, dash, or underscore."
    }

    private var scrollBottomPadding: CGFloat {
        AppSpacing.lg
    }

    private func profileSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            XBillSectionHeader(title)
            content()
        }
    }

    @ViewBuilder
    private var notificationsSection: some View {
        if notificationStatus.allowsPushRegistration {
            XBillFormSection {
                VStack(spacing: AppSpacing.sm) {
                    XBillSettingsRow(icon: "plus.circle", title: "New Expenses") {
                        Toggle("", isOn: $prefPushExpense)
                            .labelsHidden()
                            .tint(AppColors.primary)
                            .onChange(of: prefPushExpense) { _, value in
                                CacheService.defaults.set(value, forKey: NotificationService.expensePreferenceKey)
                            }
                    }

                    Divider()
                        .overlay(AppColors.border)

                    XBillSettingsRow(icon: "checkmark.seal", title: "Settlements") {
                        Toggle("", isOn: $prefPushSettlement)
                            .labelsHidden()
                            .tint(AppColors.primary)
                            .onChange(of: prefPushSettlement) { _, value in
                                CacheService.defaults.set(value, forKey: NotificationService.settlementPreferenceKey)
                            }
                    }

                    Divider()
                        .overlay(AppColors.border)

                    XBillSettingsRow(icon: "bubble.left", title: "Comments") {
                        Toggle("", isOn: $prefPushComment)
                            .labelsHidden()
                            .tint(AppColors.primary)
                            .onChange(of: prefPushComment) { _, value in
                                CacheService.defaults.set(value, forKey: NotificationService.commentPreferenceKey)
                            }
                    }
                }
            }
        } else {
            XBillFormSection {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    XBillSettingsRow(
                        icon: "bell.badge",
                        title: notificationPermissionTitle,
                        subtitle: notificationPermissionSubtitle
                    ) {
                        notificationPermissionAction
                    }

                    Text("Expense, settlement, and comment notification preferences are available after notifications are enabled.")
                        .font(.appCaption)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var notificationPermissionTitle: String {
        switch notificationStatus {
        case .denied:
            return "Notifications Off"
        case .notDetermined:
            return "Enable Notifications"
        default:
            return "Notifications Unavailable"
        }
    }

    private var notificationPermissionSubtitle: String {
        switch notificationStatus {
        case .denied:
            return "Use iOS Settings to turn them on."
        case .notDetermined:
            return "Get group and expense updates."
        default:
            return "Notification permission is not currently available."
        }
    }

    @ViewBuilder
    private var notificationPermissionAction: some View {
        switch notificationStatus {
        case .notDetermined:
            Button {
                Task { await requestNotificationsFromProfile() }
            } label: {
                if isRequestingNotifications {
                    ProgressView()
                } else {
                    Text("Enable")
                        .font(.appCaption)
                        .fontWeight(.semibold)
                }
            }
            .disabled(isRequestingNotifications)
        case .denied:
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.appCaption)
            .fontWeight(.semibold)
        default:
            EmptyView()
        }
    }

    @MainActor
    private func refreshNotificationStatus() async {
        notificationStatus = await NotificationService.shared.authorizationStatus()
        if notificationStatus == .denied {
            try? await AuthService.shared.deleteDeviceTokens()
        }
    }

    @MainActor
    private func loadNotificationPreferences() {
        prefPushExpense = CacheService.defaults.bool(forKey: NotificationService.expensePreferenceKey)
        prefPushSettlement = CacheService.defaults.bool(forKey: NotificationService.settlementPreferenceKey)
        prefPushComment = CacheService.defaults.bool(forKey: NotificationService.commentPreferenceKey)
    }

    @MainActor
    private func requestNotificationsFromProfile() async {
        isRequestingNotifications = true
        defer { isRequestingNotifications = false }

        let granted = (try? await NotificationService.shared.requestAuthorization()) ?? false
        notificationStatus = await NotificationService.shared.authorizationStatus()

        if granted || notificationStatus.allowsPushRegistration {
            NotificationService.shared.enableDefaultPreferencesAfterPermissionIfNeeded()
            loadNotificationPreferences()
            UIApplication.shared.registerForRemoteNotifications()
        } else {
            try? await AuthService.shared.deleteDeviceTokens()
        }
    }

    @ViewBuilder
    private func validationText(_ message: String?) -> some View {
        if let message {
            Text(message)
                .font(.appCaption)
                .foregroundStyle(AppColors.error)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        VStack(spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.md) {
                Button("Terms of Service") { showTerms = true }
                    .font(.appCaption)
                    .foregroundStyle(AppColors.textTertiary)
                    .underline()

                Button("Privacy Policy") { showPrivacy = true }
                    .font(.appCaption)
                    .foregroundStyle(AppColors.textTertiary)
                    .underline()
            }
            .buttonStyle(.plain)

            Text("xBill v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")")
                .font(.appCaption)
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.md)
    }

    // MARK: - Edit Sheet

    private var editSheet: some View {
        NavigationStack {
            XBillScreenContainer(
                horizontalPadding: AppSpacing.lg,
                bottomPadding: AppSpacing.floatingActionBottomPadding
            ) {
                XBillPageHeader(
                    title: "Edit Profile",
                    subtitle: "Update your display name and avatar.",
                    showsBackButton: true,
                    backAction: {
                        selectedAvatar = nil
                        isEditing = false
                    }
                )
                .padding(.horizontal, -AppSpacing.lg)

                Button {
                    showAvatarPicker = true
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Group {
                            if let selected = selectedAvatar {
                                Image(uiImage: selected)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                AvatarView(name: vm.initials, url: vm.user?.avatarURL, size: XBillIcon.avatarLg)
                            }
                        }
                        .frame(width: XBillIcon.avatarLg, height: XBillIcon.avatarLg)
                        .clipShape(Circle())

                        Image(systemName: "camera.circle.fill")
                            .font(.appH2)
                            .foregroundStyle(AppColors.textInverse, AppColors.primary)
                            .offset(x: AppSpacing.xs, y: AppSpacing.xs)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Choose profile photo")

                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    XBillSectionHeader("Display Name")
                    XBillTextField(placeholder: "Your name", text: $vm.displayName)
                        .accessibilityIdentifier("xBill.profile.editNameField")
                }
            } stickyBottom: {
                XBillPrimaryButton(
                    title: "Save",
                    icon: "checkmark",
                    isLoading: vm.isLoading,
                    isDisabled: vm.isLoading
                ) {
                    Task {
                        await vm.saveProfile(avatarImage: selectedAvatar)
                        if vm.isSaved {
                            selectedAvatar = nil
                            isEditing = false
                        }
                    }
                }
                .accessibilityIdentifier("xBill.profile.editSaveButton")
                .padding(AppSpacing.md)
                .background(.ultraThinMaterial)
            }
            .navigationBarBackButtonHidden()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAvatarPicker) {
                PhotoPickerView(selectedImage: $selectedAvatar)
                    .ignoresSafeArea()
            }
        }
    }
}

#Preview("Profile") {
    ProfileView(vm: ProfileViewModel())
}

#Preview("Profile Dark") {
    ProfileView(vm: ProfileViewModel())
        .preferredColorScheme(.dark)
}

#Preview("Profile Long Email") {
    ProfileView(vm: previewProfileViewModel(
        name: "Vijay Goyal",
        email: "vijay.goyal.with.a.very.long.email.address@example-company-domain.com"
    ), loadsOnAppear: false)
}

#Preview("Profile Long Name") {
    ProfileView(vm: previewProfileViewModel(
        name: "Vijay Goyal With A Very Long Display Name",
        email: "vijay@example.com"
    ), loadsOnAppear: false)
}

@MainActor
private func previewProfileViewModel(name: String, email: String) -> ProfileViewModel {
    let vm = ProfileViewModel()
    vm.user = User(
        id: UUID(),
        email: email,
        displayName: name,
        avatarURL: nil,
        createdAt: .now
    )
    vm.totalGroupsCount = 4
    vm.totalExpensesCount = 28
    vm.lifetimePaid = 420
    vm.displayName = name
    vm.venmoHandle = "@vijay"
    vm.paypalHandle = email
    return vm
}
