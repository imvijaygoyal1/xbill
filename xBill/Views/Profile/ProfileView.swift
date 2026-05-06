//
//  ProfileView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI
import UIKit

// MARK: - ImagePicker

private struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.selectedImage = info[.originalImage] as? UIImage
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
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

    @AppStorage("prefPushExpense") private var prefPushExpense = true
    @AppStorage("prefPushSettlement") private var prefPushSettlement = true
    @AppStorage("prefPushComment") private var prefPushComment = true

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
                Text("This permanently removes your profile and signs you out. Expenses you created will remain in your groups.")
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
                    .init(title: "Total Paid", value: vm.lifetimePaid.formatted(currencyCode: "USD"))
                ])
            }

            profileSection("Payment Handles") {
                XBillFormSection {
                    VStack(spacing: AppSpacing.lg) {
                        XBillPaymentHandleRow(
                            providerName: "Venmo",
                            systemImage: "dollarsign.circle.fill",
                            placeholder: "@venmo-handle",
                            text: $vm.venmoHandle
                        )

                        Divider()
                            .overlay(AppColors.border)

                        XBillPaymentHandleRow(
                            providerName: "PayPal",
                            systemImage: "p.circle.fill",
                            placeholder: "paypal@email.com",
                            text: $vm.paypalEmail,
                            keyboardType: .emailAddress
                        )
                    }
                }
            }

            profileSection("Notifications") {
                XBillFormSection {
                    VStack(spacing: AppSpacing.sm) {
                        XBillSettingsRow(icon: "plus.circle", title: "New Expenses") {
                            Toggle("", isOn: $prefPushExpense)
                                .labelsHidden()
                                .tint(AppColors.primary)
                        }

                        Divider()
                            .overlay(AppColors.border)

                        XBillSettingsRow(icon: "checkmark.seal", title: "Settlements") {
                            Toggle("", isOn: $prefPushSettlement)
                                .labelsHidden()
                                .tint(AppColors.primary)
                        }

                        Divider()
                            .overlay(AppColors.border)

                        XBillSettingsRow(icon: "bubble.left", title: "Comments") {
                            Toggle("", isOn: $prefPushComment)
                                .labelsHidden()
                                .tint(AppColors.primary)
                        }
                    }
                }
            }

            profileSection("Security") {
                XBillFormSection {
                    XBillSettingsRow(
                        icon: AppLockService.shared.lockIconName,
                        title: "Require Face ID / Passcode"
                    ) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { AppLockService.shared.isEnabled },
                                set: { AppLockService.shared.isEnabled = $0 }
                            )
                        )
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

                        Divider()
                            .overlay(AppColors.border)

                        XBillSettingsRow(
                            icon: "trash",
                            title: "Delete account",
                            subtitle: "Permanently remove your profile.",
                            isDestructive: true,
                            action: { showDeleteConfirm = true }
                        )
                    }
                }
            }

            footer
        }
    }

    private var scrollBottomPadding: CGFloat {
        AppSpacing.xxl + AppSpacing.floatingActionBottomPadding
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

            Text("xBill v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
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
                .padding(AppSpacing.md)
                .background(.ultraThinMaterial)
            }
            .navigationBarBackButtonHidden()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAvatarPicker) {
                ImagePicker(selectedImage: $selectedAvatar, isPresented: $showAvatarPicker)
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
    vm.paypalEmail = email
    return vm
}
