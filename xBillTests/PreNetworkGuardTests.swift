//
//  PreNetworkGuardTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  Guards that reject bad input **before** any network call, and are therefore reachable from a
//  unit test without a seam or a fake.
//
//  This is deliberately narrow. `IOUService`, `FriendService` and `CommentService` are otherwise
//  PostgREST query building: a "unit test" over them would assert what a fake returns, not what
//  the app does, which is the coverage-for-its-own-sake this codebase has already been bitten by
//  (UIT-01: an assertion that could never fail still counted as covered). Their real behaviour —
//  RLS, filters, affected-row counts — needs integration tests against Supabase.
//

import Testing
import Foundation
import UIKit
@testable import xBill

@Suite("Pre-network validation guards")
@MainActor
struct PreNetworkGuardTests {

    // MARK: - IOUService (M-25)

    /// M-25 mirrors the DB CHECK `created_by = lender_id OR created_by = borrower_id`. Without the
    /// client guard a caller could file an IOU between two other people, and the database would
    /// reject it — an error the user could not act on.
    @Test("Creating an IOU you are not party to is refused before any request")
    func iouRequiresCallerToBeAParty() async {
        let stranger = UUID(), lender = UUID(), borrower = UUID()

        await #expect(throws: AppError.self) {
            _ = try await IOUService.shared.createIOU(
                createdBy: stranger, lenderID: lender, borrowerID: borrower,
                amount: 10, currency: "USD", description: nil)
        }
    }

    /// The guard must admit both legitimate roles, or creating a normal IOU breaks. Asserting only
    /// the rejection would pass against a guard that refused everything.
    @Test("Both the lender and the borrower may create the IOU")
    func iouAdmitsEitherParty() async {
        let lender = UUID(), borrower = UUID()

        // Reaching the network means the guard let it through — that is the assertion. The request
        // itself then fails (no test backend), which is expected and not what is being checked.
        for creator in [lender, borrower] {
            do {
                _ = try await IOUService.shared.createIOU(
                    createdBy: creator, lenderID: lender, borrowerID: borrower,
                    amount: 10, currency: "USD", description: nil)
            } catch let error as AppError {
                if case .validationFailed(let message) = error {
                    Issue.record("A legitimate party was rejected by the guard: \(message)")
                }
            } catch {
                // Any non-AppError is a transport failure — the guard passed.
            }
        }
    }

    // MARK: - ProfileViewModel (H-17)

    /// H-17: a blank display name must be caught before the avatar upload, or a user can wipe
    /// their name and the upload still runs.
    @Test("A blank display name is rejected before any network call")
    func blankDisplayNameRejected() async {
        let vm = ProfileViewModel()
        vm.user = User(id: UUID(), email: "a@b.com", displayName: "Alice",
                       avatarURL: nil, createdAt: Date())
        vm.displayName = "   "

        await vm.saveProfile(avatarImage: nil)

        #expect(vm.errorAlert != nil, "A blank name must be refused, not silently saved.")
        #expect(!vm.isSaved)
    }

    /// Whitespace around an otherwise valid name must be trimmed rather than rejected — the guard
    /// trims and continues, and asserting only the rejection above would not catch a guard that
    /// rejected " Alice " too.
    @Test("A padded display name is trimmed, not rejected")
    func paddedDisplayNameIsTrimmed() async {
        let vm = ProfileViewModel()
        vm.user = User(id: UUID(), email: "a@b.com", displayName: "Alice",
                       avatarURL: nil, createdAt: Date())
        vm.displayName = "  Alice Chen  "

        await vm.saveProfile(avatarImage: nil)

        #expect(vm.displayName == "Alice Chen", "The stored name must be trimmed before saving.")
    }
}
