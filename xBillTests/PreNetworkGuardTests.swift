//
//  PreNetworkGuardTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  Guards that reject bad input **before** any network call, and are therefore reachable from a
//  unit test without a seam or a fake.
//
//  ⚠️ ONLY guards that return BEFORE any network call belong here. Two tests were removed on
//  2026-08-04 after they were found writing to **production**: `paddedDisplayNameIsTrimmed` set a
//  display name and called `saveProfile`, and `AuthService.updateProfile` writes using
//  `currentUserID` from the **live session** — not the `vm.user.id` the test set — so it renamed
//  the real `xbill.uitest` profile to "Alice Chen", which then broke the ledger UI fixture.
//  `iouAdmitsEitherParty` likewise called `createIOU` with valid parties and attempted a live
//  insert; it only failed harmlessly because the party UUIDs violated a foreign key.
//
//  Asserting the *positive* direction of these guards — that legitimate input is admitted —
//  needs an injection seam on `ProfileViewModel` and `IOUService`, which neither has. Until then
//  only the rejection direction is covered, and that is a real gap: a guard that refused
//  everything would satisfy these tests.
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

}
