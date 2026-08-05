//
//  PreNetworkGuardTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  Guards that reject bad input **before** any network call, and are therefore reachable from a
//  unit test without a seam or a fake.
//
//  ⚠️ Test the guard's **pure function**, never the method that calls it. `saveProfile` and
//  `createIOU` continue past their guards into the network, and services resolve the acting user
//  from the **live session** — so an earlier version of this file renamed a real profile in
//  production and attempted a live `ious` insert (TEST-01). Both guards are now extracted as
//  static pure functions precisely so a test cannot reach the database at all: a stronger
//  guarantee than remembering not to.
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
    /// client guard a caller could file an IOU between two other people and get a database error
    /// the user cannot act on.
    @Test("An IOU may only be created by its lender or borrower")
    func iouRequiresCallerToBeAParty() throws {
        let lender = UUID(), borrower = UUID(), stranger = UUID()

        #expect(throws: AppError.self) {
            try IOUService.validateParties(createdBy: stranger, lenderID: lender, borrowerID: borrower)
        }
        // Both legitimate roles must still be admitted. Asserting only the rejection would pass
        // against a guard that refused everything — which is the failure this pair exists to catch.
        #expect(throws: Never.self) {
            try IOUService.validateParties(createdBy: lender, lenderID: lender, borrowerID: borrower)
        }
        #expect(throws: Never.self) {
            try IOUService.validateParties(createdBy: borrower, lenderID: lender, borrowerID: borrower)
        }
    }

    // MARK: - ProfileViewModel (H-17)

    /// H-17: a blank name must be caught before the avatar upload, or a user can wipe their name
    /// and the upload still runs.
    @Test("A display name is rejected only when it is genuinely empty")
    func displayNameValidation() {
        #expect(ProfileViewModel.validatedDisplayName("") == nil)
        #expect(ProfileViewModel.validatedDisplayName("   ") == nil)
        #expect(ProfileViewModel.validatedDisplayName("\n\t ") == nil)

        // Padding is trimmed, not rejected — the other half of the guard, and the half a
        // rejection-only test would silently lose.
        #expect(ProfileViewModel.validatedDisplayName("  Alice Chen  ") == "Alice Chen")
        #expect(ProfileViewModel.validatedDisplayName("Bob") == "Bob")
    }

    /// The guard still has to be *wired in*: a pure function nothing calls protects nothing.
    /// This is the one assertion that goes through the view model, and it is safe because a blank
    /// name returns before any network call.
    @Test("saveProfile refuses a blank name and does not report success")
    func saveProfileHonoursTheGuard() async {
        let vm = ProfileViewModel()
        vm.user = User(id: UUID(), email: "a@b.com", displayName: "Alice",
                       avatarURL: nil, createdAt: Date())
        vm.displayName = "   "

        await vm.saveProfile(avatarImage: nil)

        #expect(vm.errorAlert != nil, "A blank name must be refused, not silently saved.")
        #expect(!vm.isSaved)
    }

}
