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
    var isEditing:    Bool    = false
    var errorAlert:   ErrorAlert?

    // Stats
    var totalGroupsCount:   Int     = 0
    var totalExpensesCount: Int     = 0
    var lifetimePaid:       Decimal = .zero
    var primaryCurrency:    String  = "USD"

    private let auth           = AuthService.shared
    private let groupService   = GroupService.shared
    private let expenseService = ExpenseService.shared

    // MARK: - Load

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded: User
            if let cached = user {
                // User already seeded from AuthViewModel via MainTabView.onChange —
                // reuse it to avoid a redundant supabase.auth.session call, which
                // can hit the Supabase Auth rate limit when multiple callers
                // (auth listener, homeVM, profileVM) all fire on the same startup.
                loaded = cached
            } else {
                loaded = try await auth.currentUser()
                user = loaded
            }
            // Only overwrite the editable display fields when the user is not
            // actively editing them — otherwise an in-flight background refresh
            // would silently discard unsaved changes.
            if !isEditing {
                displayName  = loaded.displayName
                venmoHandle  = loaded.venmoHandle ?? ""
                paypalEmail  = loaded.paypalEmail ?? ""
            }
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

            // M-34: profile stats don't need maximum parallelism — fetch groups
            // sequentially to avoid firing 20+ concurrent DB queries at once.
            // Cap concurrency at 5 to balance latency against DB connection pressure.
            let concurrencyLimit = 5
            var index = 0
            while index < groups.count {
                let batch = groups[index ..< min(index + concurrencyLimit, groups.count)]
                await withTaskGroup(of: (Int, Decimal).self) { taskGroup in
                    for group in batch {
                        taskGroup.addTask {
                            let expenses = (try? await self.expenseService.fetchExpenses(groupID: group.id)) ?? []
                            // M-52: exclude recurring template expenses (recurrence != .none
                            // AND nextOccurrenceDate != nil) — they are schedule placeholders,
                            // not real transactions, so they should not inflate lifetimePaid.
                            let realExpenses = expenses.filter {
                                $0.recurrence == .none || $0.nextOccurrenceDate == nil
                            }
                            // totalExpensesCount = real expenses paid by this user
                            let paidExpenses = realExpenses.filter { $0.payerID == userID }
                            let paid = paidExpenses.reduce(Decimal.zero) { $0 + $1.amount }
                            return (paidExpenses.count, paid)
                        }
                    }
                    for await (count, paid) in taskGroup {
                        expenseCount += count
                        totalPaid    += paid
                    }
                }
                index += concurrencyLimit
            }

            totalExpensesCount = expenseCount
            lifetimePaid       = totalPaid

            let freq = groups.reduce(into: [String: Int]()) { $0[$1.currency, default: 0] += 1 }
            primaryCurrency = freq.max(by: { $0.value < $1.value })?.key ?? "USD"
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

        // H-17: validate display name before any network calls.
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorAlert = ErrorAlert(title: "Name required", message: "Please enter a display name.")
            return
        }
        displayName = trimmedName

        isLoading = true
        isSaved   = false
        defer { isLoading = false }

        do {
            let handle = venmoHandle.trimmingCharacters(in: .whitespaces)
            let paypal = paypalEmail.trimmingCharacters(in: .whitespaces)

            // H-16: resolve the final avatar URL first, then do ONE profile write.
            // This eliminates the stale-URL first write and the race where step 2 fails
            // while the DB already has the old URL from step 1.
            let finalAvatarURL: URL?
            if let image = avatarImage {
                finalAvatarURL = try await auth.uploadAvatar(image, userID: user.id)
            } else {
                finalAvatarURL = user.avatarURL
            }

            let updated = try await auth.updateProfile(
                displayName: trimmedName,
                avatarURL: finalAvatarURL,
                venmoHandle: handle.isEmpty ? nil : handle,
                paypalEmail: paypal.isEmpty ? nil : paypal
            )
            self.user = updated
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
