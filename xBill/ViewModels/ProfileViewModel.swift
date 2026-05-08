//
//  ProfileViewModel.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import UIKit
import Observation

@Observable
@MainActor
final class ProfileViewModel {

    // MARK: - State

    var user:         User?
    var displayName:  String  = ""
    var venmoHandle:  String  = ""
    var paypalEmail:  String  = ""
    var isLoading:    Bool    = false
    var isSaved:      Bool    = false
    var errorAlert:   ErrorAlert?

    // Stats
    var totalGroupsCount:   Int     = 0
    var totalExpensesCount: Int     = 0
    var lifetimePaid:       Decimal = .zero

    private let auth           = AuthService.shared
    private let groupService   = GroupService.shared
    private let expenseService = ExpenseService.shared

    // MARK: - Load

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded  = try await auth.currentUser()
            user        = loaded
            displayName = loaded.displayName
            await loadStats(userID: loaded.id)
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }

    // MARK: - Stats

    private func loadStats(userID: UUID) async {
        do {
            let groups       = try await groupService.fetchGroups(for: userID)
            totalGroupsCount = groups.count

            var expenseCount = 0
            var totalPaid    = Decimal.zero

            await withTaskGroup(of: (Int, Decimal).self) { taskGroup in
                for group in groups {
                    taskGroup.addTask {
                        let expenses = (try? await self.expenseService.fetchExpenses(groupID: group.id)) ?? []
                        // totalExpensesCount = expenses paid by this user (not all group expenses)
                        let paid = expenses
                            .filter { $0.payerID == userID }
                            .reduce(Decimal.zero) { $0 + $1.amount }
                        return (expenses.filter { $0.payerID == userID }.count, paid)
                    }
                }
                for await (count, paid) in taskGroup {
                    expenseCount += count
                    totalPaid    += paid
                }
            }

            totalExpensesCount = expenseCount
            lifetimePaid       = totalPaid
        } catch {
            // Re-throw auth errors so the caller's session-invalid path can handle them;
            // swallow all other non-critical stats errors silently.
            if case AppError.unauthenticated = AppError.from(error) {
                self.errorAlert = ErrorAlert(title: "Session Expired", message: "Please sign in again.")
            }
        }
    }

    // MARK: - Save Profile

    func saveProfile(avatarImage: UIImage?) async {
        guard let user else { return }
        isLoading = true
        isSaved   = false
        defer { isLoading = false }

        do {
            // Update the profile row first. If the upload later fails, the profile
            // remains consistent and no orphaned storage object is produced.
            let updated = try await auth.updateProfile(displayName: displayName, avatarURL: user.avatarURL)
            self.user   = updated

            if let image = avatarImage {
                let newURL  = try await auth.uploadAvatar(image, userID: user.id)
                let withAvatar = try await auth.updateProfile(displayName: displayName, avatarURL: newURL)
                self.user  = withAvatar
            }
            isSaved = true
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }

    // MARK: - Sign Out

    func signOut() async {
        do {
            try await auth.signOut()
            // Clear all PII fields so they don't appear briefly if VM is reused
            user                = nil
            displayName         = ""
            venmoHandle         = ""
            paypalEmail         = ""
            totalGroupsCount    = 0
            totalExpensesCount  = 0
            lifetimePaid        = .zero
        } catch {
            self.errorAlert = ErrorAlert(title: "Sign Out Failed", message: error.localizedDescription)
        }
    }

    // MARK: - Delete Account

    func deleteAccount() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await auth.deleteAccount()
        } catch {
            self.errorAlert = ErrorAlert(
                title: "Could not delete account",
                message: error.localizedDescription
            )
        }
    }

    // MARK: - Computed

    var initials: String {
        guard let name = user?.displayName, !name.isEmpty else { return "?" }
        return name.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
    }
}
