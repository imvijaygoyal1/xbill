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
        picker.delegate   = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.selectedImage = info[.originalImage] as? UIImage
            parent.isPresented   = false
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

    @State private var isEditing          = false
    @State private var showSignOutConfirm   = false
    @State private var showDeleteConfirm    = false
    @State private var selectedAvatar: UIImage? = nil
    @State private var showAvatarPicker   = false
    @State private var showPrivacy        = false
    @State private var showTerms          = false
    @State private var showMyQR           = false

    @AppStorage("prefPushExpense")    private var prefPushExpense    = true
    @AppStorage("prefPushSettlement") private var prefPushSettlement = true
    @AppStorage("prefPushComment")    private var prefPushComment    = true

    var body: some View {
        NavigationStack {
            List {
                // Avatar & name header
                Section {
                    XBillProfileCard(
                        user: vm.user,
                        initials: vm.initials,
                        onEdit: { isEditing = true },
                        onQR: { showMyQR = true }
                    )
                    .listRowInsets(EdgeInsets(top: AppSpacing.sm, leading: AppSpacing.md, bottom: AppSpacing.sm, trailing: AppSpacing.md))
                    .listRowBackground(Color.clear)
                }

                // Stats
                Section {
                    statRow(label: "Groups",     value: "\(vm.totalGroupsCount)")
                    statRow(label: "Expenses",   value: "\(vm.totalExpensesCount)")
                    HStack {
                        Text("Total Paid")
                            .font(.xbillBodyMedium)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text(vm.lifetimePaid.formatted(currencyCode: "USD"))
                            .font(.xbillSmallAmount)
                            .foregroundStyle(Color.textPrimary)
                    }
                    .listRowBackground(Color.bgCard)
                } header: {
                    Text("YOUR STATS")
                        .font(.xbillUpperLabel)
                        .tracking(1.08)
                        .foregroundStyle(Color.textTertiary)
                }

                // Payment handles
                Section {
                    VStack(alignment: .leading, spacing: XBillSpacing.sm) {
                        HStack(spacing: XBillSpacing.sm) {
                            Image(systemName: "dollarsign.circle.fill")
                                .foregroundStyle(Color.brandAccent)
                            Text("Venmo").font(.xbillLabel).foregroundStyle(Color.textSecondary)
                        }
                        XBillTextField(placeholder: "@venmo-handle", text: $vm.venmoHandle)
                    }
                    .listRowBackground(Color.bgCard)
                    .listRowSeparatorTint(Color.separator)

                    VStack(alignment: .leading, spacing: XBillSpacing.sm) {
                        HStack(spacing: XBillSpacing.sm) {
                            Image(systemName: "p.circle.fill")
                                .foregroundStyle(Color.brandAccent)
                            Text("PayPal").font(.xbillLabel).foregroundStyle(Color.textSecondary)
                        }
                        XBillTextField(placeholder: "paypal@email.com", text: $vm.paypalEmail, keyboardType: .emailAddress)
                    }
                    .listRowBackground(Color.bgCard)
                } header: {
                    Text("PAYMENT HANDLES")
                        .font(.xbillUpperLabel)
                        .tracking(1.08)
                        .foregroundStyle(Color.textTertiary)
                }

                // Notifications
                Section {
                    Toggle(isOn: $prefPushExpense) {
                        Label("New Expenses", systemImage: "plus.circle")
                            .font(.xbillBodyMedium)
                            .foregroundStyle(Color.textPrimary)
                    }
                    .tint(Color.brandPrimary)
                    .listRowBackground(Color.bgCard)

                    Toggle(isOn: $prefPushSettlement) {
                        Label("Settlements", systemImage: "checkmark.seal")
                            .font(.xbillBodyMedium)
                            .foregroundStyle(Color.textPrimary)
                    }
                    .tint(Color.brandPrimary)
                    .listRowBackground(Color.bgCard)

                    Toggle(isOn: $prefPushComment) {
                        Label("Comments", systemImage: "bubble.left")
                            .font(.xbillBodyMedium)
                            .foregroundStyle(Color.textPrimary)
                    }
                    .tint(Color.brandPrimary)
                    .listRowBackground(Color.bgCard)
                } header: {
                    Text("NOTIFICATIONS")
                        .font(.xbillUpperLabel)
                        .tracking(1.08)
                        .foregroundStyle(Color.textTertiary)
                }

                // Security
                Section {
                    Toggle(isOn: Binding(
                        get: { AppLockService.shared.isEnabled },
                        set: { AppLockService.shared.isEnabled = $0 }
                    )) {
                        Label("Require Face ID / Passcode", systemImage: AppLockService.shared.lockIconName)
                            .font(.xbillBodyMedium)
                            .foregroundStyle(Color.textPrimary)
                    }
                    .tint(Color.brandPrimary)
                    .listRowBackground(Color.bgCard)
                } header: {
                    Text("SECURITY")
                        .font(.xbillUpperLabel)
                        .tracking(1.08)
                        .foregroundStyle(Color.textTertiary)
                }

                // Sign out + Delete account
                Section {
                    XBillButton(title: "Sign Out", style: .ghost) {
                        showSignOutConfirm = true
                    }
                    .foregroundStyle(Color.moneyNegative)
                    .listRowBackground(Color.bgCard)
                    .listRowSeparator(.hidden)

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete account", systemImage: "trash")
                            .font(.xbillBodyMedium)
                            .foregroundStyle(Color.moneyNegative)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.bgCard)
                }

                // Footer
                Section {
                    VStack(spacing: 6) {
                        HStack(spacing: XBillSpacing.base) {
                            Button("Terms of Service") { showTerms = true }
                                .font(.xbillCaption)
                                .foregroundStyle(Color.textTertiary)
                                .underline()

                            Button("Privacy Policy") { showPrivacy = true }
                                .font(.xbillCaption)
                                .foregroundStyle(Color.textTertiary)
                                .underline()
                        }
                        .buttonStyle(.plain)

                        Text("xBill v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                            .font(.xbillCaption)
                            .foregroundStyle(Color.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .safariSheet(isPresented: $showPrivacy, url: XBillURLs.privacyPolicy)
                    .sheet(isPresented: $showTerms) { TermsOfServiceView() }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppColors.background)
            .listRowSeparatorTint(AppColors.border)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(AppColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .sheet(isPresented: $isEditing) {
                editSheet
            }
            .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    if let onSignOut { onSignOut() }
                    else { Task { await vm.signOut() } }
                }
                Button("Cancel", role: .cancel) { }
            }
            .confirmationDialog(
                "Delete your account?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete account", role: .destructive) {
                    Task { await vm.deleteAccount() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This permanently removes your profile and signs you out. Expenses you created will remain in your groups.")
            }
        }
        .errorAlert(item: $vm.errorAlert)
    }

    // MARK: - Edit Sheet

    private var editSheet: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()

                VStack(spacing: XBillSpacing.xl) {
                    // Avatar picker
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
                                .font(.title2)
                                .foregroundStyle(Color.textInverse, Color.brandPrimary)
                                .offset(x: 4, y: 4)
                        }
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: XBillSpacing.xs) {
                        Text("DISPLAY NAME")
                            .font(.xbillUpperLabel)
                            .tracking(1.08)
                            .foregroundStyle(Color.textTertiary)
                        XBillTextField(placeholder: "Your name", text: $vm.displayName)
                    }
                    .padding(.horizontal, XBillSpacing.xl)

                    Spacer()
                }
                .padding(.top, XBillSpacing.xl)
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        selectedAvatar = nil
                        isEditing      = false
                    }
                    .foregroundStyle(Color.brandPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await vm.saveProfile(avatarImage: selectedAvatar)
                            if vm.isSaved {
                                selectedAvatar = nil
                                isEditing      = false
                            }
                        }
                    }
                    .disabled(vm.isLoading)
                    .overlay { if vm.isLoading { ProgressView() } }
                    .foregroundStyle(Color.brandPrimary)
                }
            }
            .sheet(isPresented: $showAvatarPicker) {
                ImagePicker(selectedImage: $selectedAvatar, isPresented: $showAvatarPicker)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showMyQR) {
                if let userID = vm.user?.id {
                    MyQRCodeView(userID: userID, displayName: vm.user?.displayName ?? "")
                }
            }
        }
    }

    // MARK: - Helpers

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.xbillBodyMedium)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.xbillBodyMedium)
                .foregroundStyle(Color.textPrimary)
        }
        .listRowBackground(Color.bgCard)
    }
}

#Preview {
    ProfileView(vm: ProfileViewModel())
}
