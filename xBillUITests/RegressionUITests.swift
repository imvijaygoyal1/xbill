//
//  RegressionUITests.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import XCTest

// MARK: - RegressionUITests

@MainActor
final class RegressionUITests: XCTestCase {

    private var app: XCUIApplication!
    private struct RegressionFailure: Error {}

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 180
        app = XCUIApplication()
        launch(route: "groups")
    }

    override func tearDown() async throws {
        app = nil
        try await super.tearDown()
    }

    func testCoreGroupExpenseArchiveRegression() throws {
        try signInIfNeeded()

        let groupName = uniqueName(prefix: "Regression")
        let expenseTitle = "Regression dinner \(uniqueSuffix())"

        try createGroup(named: groupName)
        try openGroup(named: groupName)
        try addExpense(title: expenseTitle, amount: "42.50")

        let expenseRow = expenseRowButton(title: expenseTitle)
        XCTAssertTrue(expenseRow.waitForExistence(timeout: 8), "Saved expense should appear in the group expense list.")

        try openGroupTab("Balances")
        XCTAssertTrue(app.buttons["Expenses"].waitForExistence(timeout: 3), "Balances tab should load without leaving group detail.")

        try openGroupTab("Settle Up")
        XCTAssertTrue(app.buttons["Expenses"].waitForExistence(timeout: 3), "Settle Up tab should load without leaving group detail.")

        try openGroupTab("Expenses")
        try archiveCurrentGroup()
        XCTAssertTrue(groupSurfaceExists(timeout: 8), "Archiving should return to the Groups screen.")
        XCTAssertFalse(
            activeGroupButton(named: groupName).waitForExistence(timeout: 2),
            "Archived regression group should not remain in the active group list."
        )
    }

    func testPaymentReturnSurvivesAppReactivationRegression() throws {
        try signInIfNeeded()

        let groupName = uniqueName(prefix: "PaymentReturn")
        try createGroup(named: groupName)
        try openGroup(named: groupName)
        try addExpense(title: "Reactivation expense \(uniqueSuffix())", amount: "24.00")
        try openGroupTab("Settle Up")

        // Venmo uses a custom URL scheme and PayPal may return through Safari, but both
        // produce the same foreground transition in xBill.
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(
            app.staticTexts["All Settled Up!"].waitForExistence(timeout: 10)
                || app.staticTexts["Couldn’t Refresh Balances"].waitForExistence(timeout: 1)
                || app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "xBill.settleUp.recordPaymentButton.")).firstMatch.waitForExistence(timeout: 1),
            "Settle Up should resolve after app reactivation instead of remaining on Refreshing balances."
        )
        XCTAssertFalse(
            app.staticTexts["Refreshing balances…"].waitForExistence(timeout: 1),
            "The balance spinner should not remain visible after app reactivation."
        )

        // Returning from a payment handoff must never raise a generic error alert.
        // GroupDetailView loads with showError: false on both .task and the
        // scenePhase transition, but HomeViewModel.loadAll() also runs on
        // didBecomeActive and its alert is bound outside the Groups NavigationStack
        // (GroupListView), so it would present over this screen.
        XCTAssertFalse(
            app.alerts["Something went wrong"].exists,
            "Returning from a payment handoff must not present a generic error alert."
        )
        XCTAssertFalse(
            app.alerts.staticTexts["Some balances may be stale"].exists,
            "Returning from a payment handoff must not present a stale-balance alert."
        )

        try openGroupTab("Expenses")
        try archiveCurrentGroup()
    }

    func testCreateGroupValidationRegression() throws {
        try signInIfNeeded()
        try requireGroupsSurface()
        try openCreateGroupForm()

        let submitButton = app.buttons["xBill.createGroup.submitButton"]
        XCTAssertTrue(submitButton.waitForExistence(timeout: 3), "Create button should exist.")
        XCTAssertFalse(submitButton.isEnabled, "Create button should be disabled before a group name is entered.")

        let nameField = app.textFields["e.g. Weekend Trip"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3), "New group name field should be visible.")
        XCTAssertTrue(focusTextInput(nameField), "New group name field should accept keyboard focus.")
        nameField.typeText(uniqueName(prefix: "Validation"))

        XCTAssertTrue(submitButton.isEnabled, "Create button should enable after a valid group name is entered.")
        tapVisibleBackButton()
        XCTAssertTrue(groupSurfaceExists(timeout: 4), "Back should return to the Groups screen.")
    }

    func testExpenseFormValidationRegression() throws {
        try signInIfNeeded()

        let groupName = uniqueName(prefix: "ExpenseForm")
        try createGroup(named: groupName)
        try openGroup(named: groupName)

        let addExpenseButton = app.buttons["Add Expense"].firstMatch
        XCTAssertTrue(addExpenseButton.waitForExistence(timeout: 4), "Add Expense action should be available.")
        addExpenseButton.tap()

        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.Add Expense"].waitForExistence(timeout: 6))
        let saveButton = app.buttons["xBill.addExpense.saveButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 4), "Save Expense button should be visible.")
        XCTAssertFalse(saveButton.isEnabled, "Save Expense should be disabled before required fields are entered.")

        let titleField = app.textFields["xBill.addExpense.titleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 4), "Expense title field should be visible.")
        typeInto(titleField, "Validation expense \(uniqueSuffix())")
        XCTAssertFalse(saveButton.isEnabled, "Save Expense should remain disabled without an amount.")

        let amountField = app.textFields["xBill.addExpense.amountField"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 4), "Amount field should be visible.")
        typeInto(amountField, "12.34")
        XCTAssertTrue(saveButton.isEnabled, "Save Expense should enable after title and amount are entered.")

        tapVisibleBackButton()
        XCTAssertTrue(app.buttons["Group actions"].waitForExistence(timeout: 4), "Back should return to group detail.")
        launch(route: "groups")
        XCTAssertTrue(groupSurfaceExists(timeout: 8), "Validation test should return to Groups after backing out.")
    }

    func testArchiveUnarchiveRegression() throws {
        try signInIfNeeded()

        let groupName = uniqueName(prefix: "ArchiveCycle")
        try createGroup(named: groupName)
        try openGroup(named: groupName)
        try archiveCurrentGroup()

        launch(route: "groups")
        try requireGroupsSurface()
        XCTAssertTrue(groupSurfaceExists(timeout: 8), "Archiving should return to the Groups screen.")

        searchGroups(groupName)
        let archivedRow = archivedRowButton()
        XCTAssertTrue(archivedRow.waitForExistence(timeout: 4), "Archived section should be visible after archive.")
        archivedRow.tap()

        let archivedGroup = archivedGroupButton(named: groupName)
        scrollToElement(archivedGroup, maxSwipes: 4)
        XCTAssertTrue(archivedGroup.waitForExistence(timeout: 4), "Archived group should appear after expanding Archived.")
        openArchivedGroup(named: groupName)

        XCTAssertTrue(app.buttons["Group actions"].waitForExistence(timeout: 4), "Archived group detail should open.")
        app.buttons["Group actions"].tap()
        XCTAssertTrue(app.buttons["Unarchive Group"].waitForExistence(timeout: 4), "Unarchive action should be available.")
        app.buttons["Unarchive Group"].tap()
        XCTAssertTrue(app.buttons["Unarchive Group"].waitForExistence(timeout: 4), "Unarchive confirmation should appear.")
        app.buttons["Unarchive Group"].tap()

        XCTAssertTrue(groupSurfaceExists(timeout: 8), "Unarchiving should return to Groups screen.")
        XCTAssertTrue(waitForActiveGroupInGroups(named: groupName, timeout: 20), "Unarchived group should return to active list.")

        try openGroup(named: groupName)
        try archiveCurrentGroup()
        XCTAssertTrue(groupSurfaceExists(timeout: 8), "Cleanup archive should return to Groups screen.")
    }

    func testMainTabsLoadRegression() throws {
        launchMainApp(initialTab: "groups")
        try signInIfNeeded()
        dismissNotificationPromptIfNeeded()

        XCTAssertTrue(groupSurfaceExists(timeout: 8), "Groups tab should load in the main tab shell.")

        tapTab(identifier: "xBill.tab.home", label: "Home")
        dismissNotificationPromptIfNeeded()
        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.Home"].waitForExistence(timeout: 8), "Home tab should load.")

        tapTab(identifier: "xBill.tab.friends", label: "Friends")
        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.Friends"].waitForExistence(timeout: 8), "Friends tab should load.")

        tapTab(identifier: "xBill.tab.activity", label: "Recent")
        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.Recent Activity"].waitForExistence(timeout: 8), "Recent Activity tab should load.")

        tapTab(identifier: "xBill.tab.profile", label: "Profile")
        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.Profile"].waitForExistence(timeout: 8), "Profile tab should load.")

        tapTab(identifier: "xBill.tab.groups", label: "Groups")
        XCTAssertTrue(groupSurfaceExists(timeout: 8), "Groups tab should still load after tab switching.")
    }

    func testExpenseDetailCommentsRegression() throws {
        try signInIfNeeded()

        let groupName = uniqueName(prefix: "ExpenseDetail")
        let expenseTitle = "Detail expense \(uniqueSuffix())"
        let commentText = "Regression comment \(uniqueSuffix())"

        try createGroup(named: groupName)
        try openGroup(named: groupName)
        try addExpense(title: expenseTitle, amount: "18.25")
        try openExpenseDetail(title: expenseTitle)

        XCTAssertTrue(app.staticTexts[expenseTitle].waitForExistence(timeout: 6), "Expense detail title should be visible.")
        XCTAssertTrue(app.staticTexts["Split Between"].waitForExistence(timeout: 6), "Split section should be visible.")
        XCTAssertTrue(app.staticTexts["Comments"].waitForExistence(timeout: 6), "Comments section should be visible.")

        let commentField = commentFieldElement()
        XCTAssertTrue(commentField.waitForExistence(timeout: 6), "Comment field should be visible.")
        typeInto(commentField, commentText)
        postCommentButton().tap()

        XCTAssertTrue(app.staticTexts[commentText].waitForExistence(timeout: 8), "Posted comment should appear in the expense detail.")

        tapVisibleBackButton()
        XCTAssertTrue(app.buttons["Group actions"].waitForExistence(timeout: 4), "Back should return to group detail.")
        try openExpenseDetail(title: expenseTitle)
        XCTAssertTrue(app.staticTexts[commentText].waitForExistence(timeout: 8), "Posted comment should persist after reopening expense detail.")

        tapVisibleBackButton()
        try archiveCurrentGroup()
        XCTAssertTrue(groupSurfaceExists(timeout: 8), "Archiving should return to Groups screen.")
    }

    func testProfileEditAndPaymentHandleValidationRegression() throws {
        launchMainApp(initialTab: "groups")
        try signInIfNeeded()
        dismissNotificationPromptIfNeeded()

        tapTab(identifier: "xBill.tab.profile", label: "Profile")
        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.Profile"].waitForExistence(timeout: 8), "Profile tab should load.")

        let editProfile = app.buttons["Edit profile"]
        XCTAssertTrue(editProfile.waitForExistence(timeout: 8), "Edit profile action should be visible.")
        editProfile.tap()
        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.Edit Profile"].waitForExistence(timeout: 6), "Edit Profile sheet should open.")
        XCTAssertTrue(app.textFields["xBill.profile.editNameField"].waitForExistence(timeout: 6), "Edit profile name field should be visible.")
        tapVisibleBackButton()
        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.Profile"].waitForExistence(timeout: 6), "Back should dismiss Edit Profile.")

        let venmoField = app.textFields["xBill.profile.venmoField"]
        scrollToElement(venmoField)
        XCTAssertTrue(venmoField.waitForExistence(timeout: 4), "Venmo field should be available.")
        // "bad" is 3 characters; Venmo's documented minimum is 5, so this must be rejected.
        // The old copy demanded a leading "@" — PaymentHandleValidator now strips "@" when
        // present rather than requiring it, because a Venmo username does not contain one.
        typeInto(venmoField, "bad")
        let lengthMessage = app.staticTexts["Venmo handles are 5–30 characters."]
        XCTAssertTrue(lengthMessage.waitForExistence(timeout: 4), "Invalid Venmo handle should show validation.")

        // Typing up to a legal length must clear the message — otherwise the field could be
        // stuck showing an error for every input, and the assertion above would still pass.
        venmoField.typeText("die")
        XCTAssertFalse(
            lengthMessage.waitForExistence(timeout: 2),
            "A valid Venmo handle should clear the length validation message."
        )
        dismissKeyboardIfNeeded()

        let signOut = app.buttons["Sign Out"].firstMatch
        scrollToElement(signOut)
        XCTAssertTrue(signOut.waitForExistence(timeout: 6), "Sign Out row should be available.")
    }

    func testReceiptManualReviewRegression() throws {
        try signInIfNeeded()

        let groupName = uniqueName(prefix: "ReceiptManual")
        try createGroup(named: groupName)
        try openGroup(named: groupName)
        try openAddExpenseForm()

        let scanReceipt = app.buttons["xBill.addExpense.scanReceiptButton"].firstMatch
        XCTAssertTrue(scanReceipt.waitForExistence(timeout: 4), "Scan Receipt entry point should be available from Add Expense.")
        scanReceipt.tap()

        XCTAssertTrue(app.navigationBars["Scan Receipt"].waitForExistence(timeout: 6)
                      || app.staticTexts["Scan a receipt for OCR"].waitForExistence(timeout: 2),
                      "Receipt scan screen should open.")
        XCTAssertTrue(app.buttons["xBill.receiptScan.cameraButton"].waitForExistence(timeout: 4), "Camera scan action should be visible.")
        XCTAssertTrue(app.buttons["xBill.receiptScan.photoButton"].waitForExistence(timeout: 4), "Analyze photo action should be visible.")

        let manualButton = app.buttons["xBill.receiptScan.manualButton"]
        XCTAssertTrue(manualButton.waitForExistence(timeout: 4), "Manual receipt entry should be available.")
        manualButton.tap()

        XCTAssertTrue(app.navigationBars["Review Receipt"].waitForExistence(timeout: 6), "Manual receipt review should open.")
        XCTAssertTrue(app.textFields["xBill.receiptReview.merchantField"].waitForExistence(timeout: 4), "Receipt merchant field should be editable.")
        XCTAssertTrue(app.textFields["xBill.receiptReview.totalField"].waitForExistence(timeout: 4), "Receipt total field should be editable.")
        XCTAssertTrue(app.buttons["xBill.receiptReview.addItemButton"].waitForExistence(timeout: 4), "Receipt review should allow adding items.")
        XCTAssertTrue(app.buttons["xBill.receiptReview.useSplitsButton"].waitForExistence(timeout: 4), "Receipt review should expose split confirmation.")

        tapVisibleBackButton()
        tapCancelIfPossible()
        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.Add Expense"].waitForExistence(timeout: 4)
                      || app.buttons["Group actions"].waitForExistence(timeout: 2),
                      "Canceling receipt review should return to the expense or group flow.")
    }

    func testSplitModeControlsRegression() throws {
        try signInIfNeeded()

        let groupName = uniqueName(prefix: "SplitModes")
        try createGroup(named: groupName)
        try openGroup(named: groupName)
        try openAddExpenseForm()

        let titleField = app.textFields["xBill.addExpense.titleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 4), "Expense title field should be visible.")
        typeInto(titleField, "Split mode validation \(uniqueSuffix())")

        let amountField = app.textFields["xBill.addExpense.amountField"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 4), "Amount field should be visible.")
        typeInto(amountField, "30.00")
        dismissKeyboardIfNeeded()

        XCTAssertTrue(app.buttons["Equal"].waitForExistence(timeout: 4), "Equal split segment should be visible.")
        XCTAssertTrue(app.buttons["Exact"].waitForExistence(timeout: 4), "Exact split segment should be visible.")
        XCTAssertTrue(app.buttons["By %"].waitForExistence(timeout: 4), "Percentage split segment should be visible.")
        XCTAssertTrue(app.buttons["Shares"].waitForExistence(timeout: 4), "Shares split segment should be visible.")

        app.buttons["Exact"].tap()
        let exactField = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "xBill.addExpense.exactAmountField.")).firstMatch
        XCTAssertTrue(exactField.waitForExistence(timeout: 4), "Exact split mode should show amount entry fields.")

        app.buttons["Shares"].tap()
        let increaseShares = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "xBill.addExpense.increaseShares.")).firstMatch
        XCTAssertTrue(increaseShares.waitForExistence(timeout: 4), "Shares split mode should show share steppers.")

        app.buttons["By %"].tap()
        XCTAssertTrue(app.buttons["xBill.addExpense.saveButton"].waitForExistence(timeout: 4), "Percentage split mode should keep the save action available.")

        tapVisibleBackButton()
        XCTAssertTrue(app.buttons["Group actions"].waitForExistence(timeout: 4), "Back should dismiss Add Expense after split-mode validation.")
    }

    func testGroupSettingsInviteAndCurrencyLockRegression() throws {
        try signInIfNeeded()

        let groupName = uniqueName(prefix: "GroupSettings")
        try createGroup(named: groupName)
        try openGroup(named: groupName)

        let manageButton = app.buttons["xBill.group.manageButton"]
        XCTAssertTrue(manageButton.waitForExistence(timeout: 4), "Manage action should be visible on group detail.")
        manageButton.tap()

        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.Manage Group"].waitForExistence(timeout: 6)
                      || app.navigationBars["Manage Group"].waitForExistence(timeout: 2),
                      "Manage Group sheet should open.")
        XCTAssertTrue(app.textFields["xBill.groupSettings.nameField"].waitForExistence(timeout: 4), "Group name should be editable.")
        XCTAssertTrue(app.buttons["xBill.groupSettings.inviteEmailButton"].waitForExistence(timeout: 4), "Invite by Email action should be visible.")
        XCTAssertTrue(app.buttons["xBill.groupSettings.inviteLinkButton"].waitForExistence(timeout: 4), "Invite Link action should be visible.")

        app.buttons["xBill.groupSettings.inviteEmailButton"].tap()
        XCTAssertTrue(app.navigationBars["Invite Members"].waitForExistence(timeout: 6), "Invite Members sheet should open.")
        tapCancelIfPossible()

        app.buttons["xBill.groupSettings.inviteLinkButton"].tap()
        XCTAssertTrue(app.navigationBars["Invite via Link"].waitForExistence(timeout: 6), "Invite Link sheet should open.")
        tapVisibleBackButton()

        tapVisibleBackButton()
        XCTAssertTrue(app.buttons["Group actions"].waitForExistence(timeout: 4), "Back should dismiss Manage Group.")

        try addExpense(title: "Currency lock \(uniqueSuffix())", amount: "5.00")
        XCTAssertTrue(app.buttons["xBill.group.manageButton"].waitForExistence(timeout: 4), "Manage action should be visible after adding an expense.")
        app.buttons["xBill.group.manageButton"].tap()
        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.Manage Group"].waitForExistence(timeout: 6)
                      || app.navigationBars["Manage Group"].waitForExistence(timeout: 2),
                      "Manage Group sheet should reopen after adding an expense.")
        let currencyLockedMessage = app.staticTexts["xBill.groupSettings.currencyLockedMessage"]
        scrollToElement(currencyLockedMessage, maxSwipes: 3)
        XCTAssertTrue(currencyLockedMessage.waitForExistence(timeout: 6),
                      "Currency lock explanation should appear after the first expense.")
        tapVisibleBackButton()
        try archiveCurrentGroup()
    }

    func testSettleUpAndActivitySurfacesRegression() throws {
        launch(route: "groups")
        try signInIfNeeded()
        dismissNotificationPromptIfNeeded()

        let groupName = uniqueName(prefix: "SettleSurface")
        try createGroup(named: groupName)
        try openGroup(named: groupName)

        try openGroupTab("Settle Up")
        XCTAssertTrue(app.staticTexts["All Settled!"].waitForExistence(timeout: 6)
                      || app.staticTexts["All Settled Up!"].waitForExistence(timeout: 0.5)
                      || app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "xBill.settleUp.recordPaymentButton.")).firstMatch.waitForExistence(timeout: 2),
                      "Settle Up tab should show either empty state or settlement actions.")

        launchMainApp(initialTab: "groups")
        dismissNotificationPromptIfNeeded()

        tapTab(identifier: "xBill.tab.activity", label: "Recent")
        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.Recent Activity"].waitForExistence(timeout: 8), "Recent Activity tab should load.")
        let activityFilter = app.otherElements["xBill.activity.filterControl"]
        guard activityFilter.waitForExistence(timeout: 4) || app.buttons["All"].waitForExistence(timeout: 0.5) else {
            XCTAssertTrue(app.staticTexts["No Activity Yet"].waitForExistence(timeout: 4), "Empty Activity state should be visible when there are no items.")
            return
        }

        XCTAssertTrue(app.buttons["Unread"].waitForExistence(timeout: 4), "Activity Unread filter should be visible when Activity has items.")
        app.buttons["Unread"].tap()
        XCTAssertTrue(app.staticTexts["All Caught Up"].waitForExistence(timeout: 4)
                      || app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "xBill.activity.item.")).firstMatch.waitForExistence(timeout: 2)
                      || app.buttons["xBill.activity.markAllReadButton"].waitForExistence(timeout: 2),
                      "Unread Activity should show an empty state or unread items.")
    }

    /// Settle Up against a group that actually carries a debt.
    ///
    /// `testSettleUpAndActivitySurfacesRegression` above creates a fresh, single-member group, so
    /// it can only ever assert the "All Settled Up!" empty state — a single-member group cannot
    /// hold a debt. That left the entire settlements ledger with no UI coverage: none of the four
    /// defects found by device testing on 2026-08-01 (unnamed parties, an `8` prefill where
    /// `8.00` was required, unstable row identity, and a crash on delete) was reachable from this
    /// suite. This test uses the multi-member `SeedLedger-Regression` fixture so all three row
    /// kinds and both sides of the delete gate are on screen at once.
    ///
    /// Read-only by construction: it opens the Record Payment sheet and cancels. Recording would
    /// mutate the fixture and make the next run start from a different balance.
    func testSettleUpLedgerRegression() throws {
        launch(route: "groups")
        try signInIfNeeded()
        dismissNotificationPromptIfNeeded()

        let fixture = "SeedLedger-Regression"
        guard activeGroupButton(named: fixture).waitForExistence(timeout: 8) else {
            return XCTFail("""
                Fixture group "\(fixture)" is missing. The settlements-ledger UI coverage needs a \
                multi-member group with a real debt; create it with:
                  supabase db query --file scripts/seed-ledger-regression-group.sql --linked
                Failing rather than skipping, matching how this suite treats absent credentials.
                """)
        }
        // Filter the list first. Every other test opens a group it just created, which lands at
        // the top; this fixture is a long-lived group further down, where the row can exist in
        // the hierarchy (so `waitForExistence` passes) while being off-screen and not hittable,
        // so the tap silently fails to open anything.
        searchGroups(fixture)
        try openGroup(named: fixture)
        try openGroupTab("Settle Up")

        // A debt the account is party to: the button exists because migration 041's INSERT policy
        // admits either party.
        // `descendants(matching: .any)`, not `app.buttons`: `.accessibilityIdentifier` on a
        // composite SwiftUI view can land on a wrapper element rather than the inner Button, so
        // an element-type-specific query misses it. The pre-existing suite only ever used this
        // predicate as a fallback against an empty group, so it never had to match anything and
        // the mismatch stayed hidden.
        let recordButton = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "xBill.settleUp.recordPaymentButton."))
            .firstMatch
        if !recordButton.waitForExistence(timeout: 12) {
            XCTFail("""
                A debt the signed-in account is party to should offer Record Payment, but no                 element carried that identifier. Settle Up tree follows:
                \(app.debugDescription)
                """)
            return
        }

        // A debt between two OTHER members: no button, and a caption saying why. Before this the
        // row was simply dimmed with no explanation, which reads as a broken button.
        let nonPartyCaption = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "xBill.settleUp.nonPartyCaption."))
            .firstMatch
        XCTAssertTrue(nonPartyCaption.waitForExistence(timeout: 4),
                      "A debt between two other members should explain why it cannot be recorded.")

        // Recent Payments is populated, so the ledger's history surface is exercised too.
        let historyRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "xBill.paymentHistory.row."))
            .firstMatch
        XCTAssertTrue(historyRow.waitForExistence(timeout: 4),
                      "Recorded payments should be listed under Recent Payments.")

        recordButton.tap()

        let amountField = app.textFields["xBill.recordPayment.amountField"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 6), "Record Payment sheet should open.")

        // The regression that shipped to a device: the sheet prefilled via
        // `NSDecimalNumber.stringValue`, which drops trailing zeros, so an $8.00 debt appeared as
        // "8". Same behaviour made PayPal.Me ignore a settlement amount. Assert the shape, not a
        // specific figure, so the test survives a fixture whose balances change.
        let prefill = (amountField.value as? String) ?? ""
        XCTAssertTrue(
            prefill.range(of: #"^\d+\.\d{2}$"#, options: .regularExpression) != nil,
            "Prefilled amount must carry exactly two decimals; got \"\(prefill)\"."
        )

        XCTAssertTrue(app.buttons["xBill.recordPayment.confirmButton"].exists,
                      "Record Payment sheet should offer a confirm action.")

        // Cancel — see the read-only note above.
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 4), "Record Payment sheet should be cancellable.")
        cancel.tap()
        XCTAssertTrue(recordButton.waitForExistence(timeout: 6),
                      "Cancelling should return to Settle Up with the debt intact.")
    }

    /// The ledger's **write** path: recording a payment moves real money.
    ///
    /// `testSettleUpLedgerRegression` covers the settle-up surfaces read-only. This asserts that
    /// a recorded payment actually reduces the debt by exactly the amount paid — a *partial*
    /// payment, which the old `splits.is_settled` boolean could not represent at all (REV-02),
    /// and which shipped with no automated coverage.
    ///
    /// **Deliberately one-way.** Deleting a settlement is only reachable through a SwiftUI List
    /// swipe action, and XCUITest cannot open those here: the rows are not exposed as cells
    /// (settle-up rows appear as `Other`, a payment row as `StaticText`), so neither
    /// `swipeLeft()` nor an element- or window-level drag reaches the row. Eight approaches were
    /// tried and the database confirmed the delete never fired. So this test records and does not
    /// clean up after itself; `scripts/reset-ledger-regression-fixture.sql` restores the fixture
    /// and `run-coverage.sh regression-ui` runs it after every pass.
    ///
    /// A negative assertion for the delete gate was written and then **removed**: with swipes
    /// never opening, `XCTAssertFalse(deleteButton.exists)` passed unconditionally. A green check
    /// that cannot fail is worse than a missing one — see UIT-01, found the same day.
    func testSettleUpLedgerWriteRegression() throws {
        launch(route: "groups")
        try signInIfNeeded()
        dismissNotificationPromptIfNeeded()

        let fixture = "SeedLedger-Regression"
        guard activeGroupButton(named: fixture).waitForExistence(timeout: 8) else {
            return XCTFail("""
                Fixture group "\(fixture)" is missing. Create it with:
                  supabase db query --file scripts/seed-ledger-regression-group.sql --linked
                """)
        }

        searchGroups(fixture)
        try openGroup(named: fixture)
        try openGroupTab("Settle Up")

        // The row where the signed-in account is the CREDITOR — the REV-01 path, impossible to
        // record before migration 041 because RLS on `splits` admitted only the debtor.
        let creditorRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                  "xBill.settleUp.suggestionRow.", "Bob Patel owes"))
            .firstMatch
        XCTAssertTrue(creditorRow.waitForExistence(timeout: 10), "Fixture should show a debt owed to this account.")
        XCTAssertTrue(waitForLabel(creditorRow, toContain: "$8.00", timeout: 10),
                      """
                      Fixture must start at $8.00; got \(creditorRow.label). A previous run left a \
                      payment behind — run scripts/reset-ledger-regression-fixture.sql.
                      """)

        let suffix = creditorRow.identifier.replacingOccurrences(
            of: "xBill.settleUp.suggestionRow.", with: "")
        let recordButton = app.descendants(matching: .any)["xBill.settleUp.recordPaymentButton.\(suffix)"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 4), "Creditor row should offer Record Payment.")
        recordButton.tap()

        // --- WRITE ---
        let amountField = app.textFields["xBill.recordPayment.amountField"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 6), "Record Payment sheet should open.")
        amountField.tap()
        if let existing = amountField.value as? String, !existing.isEmpty {
            amountField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        amountField.typeText("1.23")
        app.buttons["xBill.recordPayment.confirmButton"].tap()

        // The debt must fall by exactly the amount paid, and the remainder stays actionable.
        XCTAssertTrue(waitForLabel(creditorRow, toContain: "$6.77", timeout: 12),
                      "$8.00 minus a $1.23 payment must render as $6.77 — the partial-payment path.")

        // The payment is recorded in history, attributed to this account.
        let paymentRow = paymentHistoryRow(containing: "$1.23")
        XCTAssertTrue(scrollUntilHittable(paymentRow), "The recorded payment should appear under Recent Payments.")
        XCTAssertTrue(paymentRow.label.contains("recorded by"), "History must show who recorded the payment.")

        // Delete is NOT asserted here — see UIT-06. `.swipeActions` and `.contextMenu` on
        // these rows cannot be opened from XCUITest (twelve approaches tried; the database
        // confirmed the delete never fired), so any assertion about it would pass without
        // testing anything. That is the UIT-01 defect, and a green check that cannot fail is
        // worse than a missing one. Deletion is covered by device testing only.
    }

    func testProfileQRCodeAndAccountCancelRegression() throws {
        launchMainApp(initialTab: "groups")
        try signInIfNeeded()
        dismissNotificationPromptIfNeeded()

        tapTab(identifier: "xBill.tab.profile", label: "Profile")
        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.Profile"].waitForExistence(timeout: 8), "Profile tab should load.")

        let qrButton = app.buttons["xBill.profile.showQRCodeButton"]
        XCTAssertTrue(qrButton.waitForExistence(timeout: 6), "Profile QR action should be visible.")
        qrButton.tap()
        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.My QR Code"].waitForExistence(timeout: 6)
                      || app.navigationBars["My QR Code"].waitForExistence(timeout: 2),
                      "My QR Code screen should open.")
        XCTAssertTrue(app.otherElements["xBill.profile.qrCodeCard"].waitForExistence(timeout: 6)
                      || app.otherElements["xBill.profile.qrIllustration"].waitForExistence(timeout: 2),
                      "QR surface should render.")
        tapVisibleBackButton()

        let deleteAccount = app.buttons["xBill.profile.deleteAccountButton"]
        scrollToElement(deleteAccount, maxSwipes: 8)
        XCTAssertTrue(deleteAccount.waitForExistence(timeout: 6), "Delete account action should be visible.")
        deleteAccount.tap()
        XCTAssertTrue(app.buttons["Delete account"].waitForExistence(timeout: 4)
                      || app.staticTexts["Delete your account?"].waitForExistence(timeout: 2),
                      "Delete account confirmation should appear.")
        tapCancelIfPossible()

        let signOut = app.buttons["xBill.profile.signOutButton"]
        scrollToElement(signOut, maxSwipes: 8)
        XCTAssertTrue(signOut.waitForExistence(timeout: 6), "Sign Out action should be visible.")
        signOut.tap()
        XCTAssertTrue(app.buttons["Sign Out"].waitForExistence(timeout: 4), "Sign Out confirmation should appear.")
        tapCancelIfPossible()
        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.Profile"].waitForExistence(timeout: 4), "Canceling account actions should leave Profile open.")
    }

    func testFriendsAddSearchRegression() throws {
        launchMainApp(initialTab: "groups")
        try signInIfNeeded()
        dismissNotificationPromptIfNeeded()

        tapTab(identifier: "xBill.tab.friends", label: "Friends")
        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.Friends"].waitForExistence(timeout: 8), "Friends tab should load.")

        let addFriend = app.buttons["Add Friend"].firstMatch
        XCTAssertTrue(addFriend.waitForExistence(timeout: 8), "Add Friend action should be available.")
        addFriend.tap()
        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.Add Friend"].waitForExistence(timeout: 8), "Add Friend sheet should open.")

        let search = app.textFields["xBill.addFriend.searchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 6), "Add Friend search field should be visible.")
        typeInto(search, "nobody-\(uniqueSuffix())@example.invalid")

        XCTAssertTrue(app.staticTexts["No matching friends"].waitForExistence(timeout: 8), "No-results state should appear for an impossible search.")
        XCTAssertTrue(app.buttons["xBill.addFriend.importContactsButton"].waitForExistence(timeout: 4), "Import Contacts action should be visible.")

        dismissKeyboardIfNeeded()
    }

    func testAuthValidationRegression() throws {
        launchSignedOut()

        XCTAssertTrue(app.staticTexts["xBill"].waitForExistence(timeout: 8), "Signed-out launch should show the auth screen.")
        app.buttons["Continue with Email"].firstMatch.tap()

        let submitButton = app.buttons["xBill.emailAuth.submitButton"]
        XCTAssertTrue(submitButton.waitForExistence(timeout: 8), "Email auth form should be visible.")
        XCTAssertFalse(submitButton.isEnabled, "Sign In should be disabled with empty fields.")

        let emailField = app.textFields["xBill.emailAuth.emailField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 4), "Email field should be visible.")
        typeInto(emailField, "invalid-email")

        let passwordField = app.secureTextFields["xBill.emailAuth.passwordField"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 4), "Password field should be visible.")
        typeInto(passwordField, "short")
        XCTAssertFalse(submitButton.isEnabled, "Sign In should remain disabled for invalid email and short password.")

        app.buttons["xBill.emailAuth.forgotPasswordButton"].tap()
        XCTAssertTrue(app.staticTexts["Reset your password"].waitForExistence(timeout: 6), "Forgot Password sheet should open.")
        dismissSheetIfPossible()

        app.buttons["xBill.emailAuth.toggleModeButton"].tap()
        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.Create Account"].waitForExistence(timeout: 6), "Create Account mode should open.")

        let confirmField = app.secureTextFields["xBill.emailAuth.confirmPasswordField"]
        XCTAssertTrue(confirmField.waitForExistence(timeout: 4), "Confirm password field should be visible in sign-up mode.")
        typeInto(confirmField, "different-password")
        XCTAssertTrue(app.staticTexts["Passwords don't match."].waitForExistence(timeout: 4), "Password mismatch validation should appear.")
    }

    // MARK: - Launch

    private func launch(route: String) {
        app.terminate()
        app.launchArguments = [
            "--uitesting",
            "--uitest-route", route,
            "-XBILL_UITEST_ROUTE", route
        ]
        app.launchEnvironment["XBILL_UITESTING"] = "1"
        app.launchEnvironment["XBILL_UITEST_ROUTE"] = route
        app.launch()
    }

    private func launchSignedOut() {
        app.terminate()
        app.launchArguments = ["--uitesting", "--reset-state"]
        app.launchEnvironment["XBILL_UITESTING"] = "1"
        app.launch()
    }

    private func launchMainApp(initialTab: String) {
        app.terminate()
        app.launchArguments = []
        app.launchEnvironment = [
            "XBILL_INITIAL_TAB": initialTab
        ]
        app.launch()
    }

    // MARK: - Auth

    private func signInIfNeeded() throws {
        if groupSurfaceExists(timeout: 4) { return }
        tapGroupsTabIfPossible()
        if groupSurfaceExists(timeout: 4) { return }

        guard let email = testCredential(named: "XBILL_TEST_EMAIL"),
              let password = testCredential(named: "XBILL_TEST_PASSWORD") else {
            XCTFail("Set XBILL_TEST_EMAIL and XBILL_TEST_PASSWORD to run authenticated regression tests.")
            throw RegressionFailure()
        }

        for _ in 0..<2 {
            launchSignedOut()
            try submitEmailSignIn(email: email, password: password)
            if waitForSignedInGroupsSurface() {
                return
            }
        }

        XCTFail("Signed-in Groups surface should load.")
        throw RegressionFailure()
    }

    private func submitEmailSignIn(email: String, password: String) throws {
        let emailButton = app.buttons["Continue with Email"].firstMatch
        if emailButton.waitForExistence(timeout: 8) {
            XCTAssertTrue(tapElement(emailButton), "Continue with Email should be tappable.")
        }

        if app.staticTexts["xBill.pageHeader.title.Create Account"].waitForExistence(timeout: 1) {
            XCTAssertTrue(tapElement(app.buttons["xBill.emailAuth.toggleModeButton"]),
                          "Email auth mode toggle should be tappable.")
        }

        let submitButton = app.buttons["xBill.emailAuth.submitButton"]
        XCTAssertTrue(submitButton.waitForExistence(timeout: 8), "Email auth form should be visible.")

        let emailField = app.textFields["xBill.emailAuth.emailField"].exists
            ? app.textFields["xBill.emailAuth.emailField"]
            : app.textFields["you@example.com"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 4), "Email field should be visible.")
        clearAndType(email, into: emailField)

        let passwordField = app.secureTextFields["xBill.emailAuth.passwordField"].exists
            ? app.secureTextFields["xBill.emailAuth.passwordField"]
            : app.secureTextFields["Min. 8 characters"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 4), "Password field should be visible.")
        clearAndType(password, into: passwordField)

        XCTAssertTrue(tapElement(submitButton), "Email auth submit button should be tappable.")
    }

    private func waitForSignedInGroupsSurface() -> Bool {
        for _ in 0..<3 {
            completeOnboardingIfNeeded()
            dismissNotificationPromptIfNeeded()
            if groupSurfaceExists(timeout: 8) {
                return true
            }
            tapGroupsTabIfPossible()
            dismissNotificationPromptIfNeeded()
            if groupSurfaceExists(timeout: 4) {
                return true
            }
            launch(route: "groups")
        }
        return false
    }

    private func completeOnboardingIfNeeded() {
        let skip = app.buttons["Skip"].firstMatch
        if skip.waitForExistence(timeout: 3) {
            _ = tapElement(skip)
            return
        }
        let next = app.buttons["Next"].firstMatch
        for _ in 0..<4 where next.waitForExistence(timeout: 1) {
            _ = tapElement(next)
        }
        let getStarted = app.buttons["Get Started"].firstMatch
        if getStarted.waitForExistence(timeout: 2) {
            _ = tapElement(getStarted)
        }
    }

    private func testCredential(named key: String) -> String? {
        if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty, !value.hasPrefix("$(") {
            return value
        }
        if let value = Bundle(for: Self.self).object(forInfoDictionaryKey: key) as? String,
           !value.isEmpty,
           !value.hasPrefix("$(") {
            return value
        }
        if let url = Bundle(for: Self.self).url(forResource: "UITestCredentials", withExtension: "plist"),
           let credentials = NSDictionary(contentsOf: url),
           let value = credentials[key] as? String,
           !value.isEmpty {
            return value
        }
        return nil
    }

    private func dismissNotificationPromptIfNeeded() {
        let notNow = app.buttons["Not Now"].firstMatch
        if notNow.waitForExistence(timeout: 2) {
            _ = tapElement(notNow)
        }
    }

    private func dismissSheetIfPossible() {
        if app.buttons["Cancel"].firstMatch.waitForExistence(timeout: 2) {
            app.buttons["Cancel"].firstMatch.tap()
        } else {
            tapVisibleBackButton()
        }
    }

    private func tapCancelIfPossible() {
        let cancelButton = app.buttons["Cancel"].firstMatch
        if cancelButton.waitForExistence(timeout: 2) {
            cancelButton.tap()
            return
        }

        let cancelElement = app.descendants(matching: .any)["Cancel"].firstMatch
        if cancelElement.waitForExistence(timeout: 1) {
            cancelElement.tap()
            return
        }

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
    }

    private func dismissKeyboardIfNeeded() {
        guard app.keyboards.firstMatch.exists else { return }

        let appDoneButton = app.buttons["xBill.keyboard.doneButton"].firstMatch
        if appDoneButton.exists {
            appDoneButton.tap()
            return
        }

        let returnKey = app.keyboards.buttons["Return"].firstMatch
        if returnKey.exists {
            returnKey.tap()
            return
        }

        let doneKey = app.keyboards.buttons["Done"].firstMatch
        if doneKey.exists {
            doneKey.tap()
            return
        }

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
    }

    /// Focuses an element and types, asserting the keyboard actually appeared first.
    ///
    /// `element.tap()` followed by `typeText` is the pattern behind two flakes and one 67-minute
    /// hang: XCUITest raises "Neither element nor any descendant has keyboard focus" — or simply
    /// wedges — when the tap did not focus the field. `focusTextInput` retries and confirms the
    /// keyboard, so failures surface as an assertion rather than a stuck run.
    private func typeInto(_ element: XCUIElement, _ text: String) {
        XCTAssertTrue(focusTextInput(element), "Field should accept keyboard focus before typing.")
        element.typeText(text)
    }

    private func clearAndType(_ text: String, into element: XCUIElement) {
        typeInto(element, String(repeating: XCUIKeyboardKey.delete.rawValue, count: 80))
        element.typeText(text)
    }

    private func focusTextInput(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }

        for _ in 0..<3 {
            if element.isHittable {
                element.tap()
            } else {
                element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }

            if app.keyboards.firstMatch.waitForExistence(timeout: 1) {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        return app.keyboards.firstMatch.exists
    }

    // MARK: - Groups

    private func openCreateGroupForm() throws {
        dismissNotificationPromptIfNeeded()

        if app.staticTexts["xBill.pageHeader.title.New Group"].waitForExistence(timeout: 1) {
            return
        }

        for candidate in [
            app.buttons["xBill.groups.createButton"],
            app.buttons["Create Group"].firstMatch
        ] where candidate.waitForExistence(timeout: 2) {
            if tapElement(candidate) {
                if app.staticTexts["xBill.pageHeader.title.New Group"].waitForExistence(timeout: 3) {
                    return
                }
            }
        }

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.095)).tap()
        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.New Group"].waitForExistence(timeout: 6), "New Group form should open.")
    }

    private func createGroup(named groupName: String) throws {
        try requireGroupsSurface()
        try openCreateGroupForm()
        let nameField = app.textFields["e.g. Weekend Trip"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3), "New group name field should be visible.")
        XCTAssertTrue(focusTextInput(nameField), "New group name field should accept keyboard focus.")
        nameField.typeText(groupName)
        app.buttons["xBill.createGroup.submitButton"].tap()

        XCTAssertTrue(activeGroupButton(named: groupName).waitForExistence(timeout: 8), "Created group should appear in Groups list.")
    }

    private func openGroup(named groupName: String) throws {
        let group = activeGroupButton(named: groupName)
        XCTAssertTrue(group.waitForExistence(timeout: 8), "Group row should be visible before opening detail.")
        group.tap()
        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.\(groupName)"].waitForExistence(timeout: 8)
                      || app.buttons["Group actions"].waitForExistence(timeout: 4),
                      "Group detail should open.")
        XCTAssertTrue(app.buttons["Group actions"].waitForExistence(timeout: 4), "Group detail actions should be available.")
    }

    private func archiveCurrentGroup() throws {
        let actions = app.buttons["Group actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 4), "Group actions should be available before archive.")
        XCTAssertTrue(tapElement(actions), "Group actions should be tappable before archive.")
        XCTAssertTrue(app.buttons["Archive Group"].waitForExistence(timeout: 4), "Archive action should be available.")
        XCTAssertTrue(tapElement(app.buttons["Archive Group"]), "Archive action should be tappable.")
        XCTAssertTrue(app.buttons["Archive Group"].waitForExistence(timeout: 4), "Archive confirmation should appear.")
        XCTAssertTrue(tapElement(app.buttons["Archive Group"]), "Archive confirmation should be tappable.")
        returnToGroupsSurfaceIfNeeded()
    }

    private func activeGroupButton(named name: String) -> XCUIElement {
        activeGroupButtons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
    }

    private func archivedGroupButton(named name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", name, " group, archived")).firstMatch
    }

    private func archivedRowButton() -> XCUIElement {
        let identifierMatch = app.buttons["xBill.groups.archivedSectionButton"]
        if identifierMatch.exists { return identifierMatch }
        return app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Archived")).firstMatch
    }

    private func openArchivedGroup(named name: String) {
        let group = archivedGroupButton(named: name)
        for _ in 0..<3 {
            scrollToElement(group, maxSwipes: 2)
            if group.exists {
                group.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                if app.buttons["Group actions"].waitForExistence(timeout: 3)
                    || app.staticTexts["xBill.pageHeader.title.\(name)"].waitForExistence(timeout: 1) {
                    return
                }
            }
        }
    }

    // MARK: - Ledger write helpers



    /// Scrolls until the element is actually hittable.
    ///
    /// `waitForExistence` is true for elements that exist in the hierarchy but are **off-screen**,
    /// and a swipe gesture on an off-screen element silently does nothing — which is why the
    /// payment-row cleanup appeared to run and changed nothing. Recent Payments sits below the
    /// suggestion rows, so it is off-screen on first render.
    @discardableResult
    private func scrollUntilHittable(_ element: XCUIElement, maxSwipes: Int = 6) -> Bool {
        guard element.waitForExistence(timeout: 4) else { return false }
        for _ in 0..<maxSwipes {
            if element.isHittable { return true }
            app.swipeUp()
        }
        return element.isHittable
    }

    private func paymentHistoryRow(containing text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                  "xBill.paymentHistory.row.", text))
            .firstMatch
    }

    /// Polls an element's `label`, which — unlike existence — is not covered by
    /// `waitForExistence`. The row object stays the same while its amount changes, so waiting for
    /// existence would return instantly and assert the *old* figure.
    private func waitForLabel(_ element: XCUIElement, toContain text: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, element.label.contains(text) { return true }
            _ = element.waitForExistence(timeout: 0.3)
        }
        return false
    }


    private func searchGroups(_ text: String) {
        for _ in 0..<3 {
            let searchField = groupsSearchField()
            if searchField.waitForExistence(timeout: 2) {
                // `focusTextInput` rather than a bare `tap()`: it confirms the keyboard actually
                // appeared and retries if not. Typing into an unfocused field raises "Neither
                // element nor any descendant has keyboard focus", which fails the whole test as
                // a runtime error rather than an assertion — a flake this suite hit twice.
                guard focusTextInput(searchField) else {
                    app.swipeDown()
                    continue
                }
                if let value = searchField.value as? String, !value.isEmpty, value != "Search groups" {
                    let fieldClearButton = searchField.buttons["Clear text"]
                    if fieldClearButton.exists {
                        fieldClearButton.tap()
                    }
                    let clearSearchButton = app.buttons["Clear search"]
                    if clearSearchButton.exists {
                        clearSearchButton.tap()
                    }
                }
                searchField.typeText(text)
                dismissKeyboardIfNeeded()
                return
            }
            app.swipeDown()
        }
    }

    private func waitForActiveGroupInGroups(named name: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            launch(route: "groups")
            dismissNotificationPromptIfNeeded()
            if groupSurfaceExists(timeout: 4) {
                searchGroups(name)
                let activeGroup = activeGroupButton(named: name)
                scrollToElement(activeGroup, maxSwipes: 3)
                if activeGroup.waitForExistence(timeout: 2) {
                    return true
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        return false
    }

    private func groupsSearchField() -> XCUIElement {
        let identifierMatch = app.textFields["xBill.groups.searchField"]
        if identifierMatch.exists { return identifierMatch }
        return app.textFields["Search groups"].firstMatch
    }

    private var activeGroupButtons: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", " group, active"))
    }

    private func requireGroupsSurface() throws {
        dismissNotificationPromptIfNeeded()
        if groupSurfaceExists(timeout: 4) { return }
        tapGroupsTabIfPossible()
        dismissNotificationPromptIfNeeded()
        guard groupSurfaceExists(timeout: 6) else {
            XCTFail("Groups surface is not available for regression run.")
            throw RegressionFailure()
        }
    }

    private func groupSurfaceExists(timeout: TimeInterval) -> Bool {
        app.staticTexts["xBill.pageHeader.title.Groups"].waitForExistence(timeout: timeout)
            || app.otherElements["xBill.home.groupsHeader"].firstMatch.waitForExistence(timeout: 0.5)
            || elementIsUsable(app.buttons["xBill.groups.createButton"], timeout: 0.5)
            || elementIsUsable(groupsSearchField(), timeout: 0.5)
            || elementIsUsable(activeGroupButtons.firstMatch, timeout: 0.5)
    }

    private func elementIsUsable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        return element.isHittable || app.frame.contains(element.frame.center)
    }

    private func tapGroupsTabIfPossible() {
        for candidate in [
            app.buttons["xBill.tab.groups"],
            app.otherElements["xBill.tab.groups"],
            app.staticTexts["xBill.tab.groups"],
            app.tabBars.buttons["Groups"],
            app.buttons["Groups"].firstMatch,
            app.otherElements["Groups"].firstMatch
        ] where candidate.waitForExistence(timeout: 0.5) {
            if candidate.isHittable {
                candidate.tap()
                return
            }
        }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.34, dy: 0.93)).tap()
    }

    private func tapTab(identifier: String, label: String) {
        for candidate in [
            app.buttons[identifier],
            app.otherElements[identifier],
            app.staticTexts[identifier],
            app.tabBars.buttons[label],
            app.buttons[label].firstMatch,
            app.otherElements[label].firstMatch
        ] where candidate.waitForExistence(timeout: 1) {
            if candidate.isHittable {
                candidate.tap()
                return
            }
        }
        XCTFail("Could not find hittable tab \(label).")
    }

    private func tapVisibleBackButton() {
        dismissKeyboardIfNeeded()

        let backButtons = app.buttons.matching(NSPredicate(format: "label == %@", "Back"))
        let appFrame = app.frame
        for index in 0..<backButtons.count {
            let button = backButtons.element(boundBy: index)
            if button.exists && button.isHittable {
                button.tap()
                return
            }
            if button.exists && appFrame.contains(button.frame.center) {
                button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                return
            }
        }

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.08)).tap()
    }

    @discardableResult
    private func tapElement(_ element: XCUIElement) -> Bool {
        guard element.waitForExistence(timeout: 2) else { return false }
        if element.isHittable {
            element.tap()
            return true
        }
        if app.frame.contains(element.frame.center) {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return true
        }
        return false
    }

    private func returnToGroupsSurfaceIfNeeded() {
        if groupSurfaceExists(timeout: 2) { return }

        for _ in 0..<3 {
            tapVisibleBackButton()
            if groupSurfaceExists(timeout: 3) { return }
        }

        tapGroupsTabIfPossible()
        if !groupSurfaceExists(timeout: 4) {
            launch(route: "groups")
        }
    }

    private func scrollToElement(_ element: XCUIElement, maxSwipes: Int = 8) {
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }

    // MARK: - Expenses

    private func openExpenseDetail(title: String) throws {
        let row = expenseRowButton(title: title)
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Expense row should exist before opening detail.")
        row.tap()
        XCTAssertTrue(app.otherElements["xBill.expenseDetail.screen"].waitForExistence(timeout: 8)
                      || app.staticTexts[title].waitForExistence(timeout: 1),
                      "Expense detail should open.")
    }

    private func addExpense(title: String, amount: String) throws {
        let addExpenseButton = app.buttons["Add Expense"].firstMatch
        XCTAssertTrue(addExpenseButton.waitForExistence(timeout: 4), "Add Expense action should be available.")
        addExpenseButton.tap()

        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.Add Expense"].waitForExistence(timeout: 6), "Add Expense screen should open.")

        let titleField = app.textFields["xBill.addExpense.titleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 4), "Expense title field should be visible.")
        typeInto(titleField, title)

        let amountField = app.textFields["xBill.addExpense.amountField"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 4), "Amount field should be visible.")
        typeInto(amountField, amount)
        dismissKeyboardIfNeeded()

        let saveButton = app.buttons["xBill.addExpense.saveButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 4), "Save Expense button should be visible.")
        XCTAssertTrue(saveButton.isEnabled, "Save Expense button should be enabled after entering required fields.")
        if !saveButton.isHittable {
            dismissKeyboardIfNeeded()
        }
        XCTAssertTrue(saveButton.waitForExistence(timeout: 4), "Save Expense button should remain visible after dismissing keyboard.")
        saveButton.tap()

        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.Add Expense"].waitForNonExistence(timeout: 12), "Add Expense screen should dismiss after save.")
        XCTAssertTrue(app.buttons["Group actions"].waitForExistence(timeout: 4), "Group detail should be visible after save.")
        XCTAssertTrue(expenseRowButton(title: title).waitForExistence(timeout: 12), "Saved expense row should appear after save.")
    }

    private func openGroupTab(_ title: String) throws {
        let tab = app.buttons[title]
        XCTAssertTrue(tab.waitForExistence(timeout: 4), "\(title) tab should exist.")
        tab.tap()
    }

    private func openAddExpenseForm() throws {
        let addExpenseButton = app.buttons["Add Expense"].firstMatch
        XCTAssertTrue(addExpenseButton.waitForExistence(timeout: 4), "Add Expense action should be available.")
        addExpenseButton.tap()
        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.Add Expense"].waitForExistence(timeout: 6), "Add Expense screen should open.")
    }

    private func expenseRowButton(title: String) -> XCUIElement {
        let identifierMatch = app.buttons["xBill.expenseRow.\(title)"]
        if identifierMatch.exists { return identifierMatch }
        let anyIdentifierMatch = app.descendants(matching: .any)["xBill.expenseRow.\(title)"]
        if anyIdentifierMatch.exists { return anyIdentifierMatch }
        return app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    private func commentFieldElement() -> XCUIElement {
        let identifierMatch = app.textFields["xBill.expenseDetail.commentField"]
        if identifierMatch.exists { return identifierMatch }
        let placeholderMatch = app.textFields["Add a comment…"].firstMatch
        if placeholderMatch.exists { return placeholderMatch }
        return app.descendants(matching: .any)["xBill.expenseDetail.commentField"]
    }

    private func postCommentButton() -> XCUIElement {
        let identifierMatch = app.buttons["xBill.expenseDetail.postCommentButton"]
        if identifierMatch.exists { return identifierMatch }
        return app.buttons["Post comment"].firstMatch
    }

    // MARK: - Test Data

    private func uniqueName(prefix: String) -> String {
        "\(prefix)-\(uniqueSuffix())"
    }

    private func uniqueSuffix() -> String {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000) % 100_000
        return "\(timestamp)-\(Int.random(in: 100...999))"
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
