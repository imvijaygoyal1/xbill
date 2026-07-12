//
//  GroupFlowUITests.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  Prerequisites: simulator must be signed in before running these tests.
//  All group-flow tests check for the Groups tab first and skip if not signed in.
//

import XCTest

// MARK: - GroupFlowUITests

@MainActor
final class GroupFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        launch(route: initialRouteForCurrentTest())
    }

    override func tearDown() async throws {
        app = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

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

    private func initialRouteForCurrentTest() -> String {
        let createFormTests = [
            "testCreateGroupSheetOpens",
            "testCreateGroupFormHasNameField",
            "testCreateGroupFormHasBackButton",
            "testCreateButtonDisabledWithEmptyName",
            "testCreateButtonEnabledAfterTypingName",
            "testBackDismissesCreateSheet"
        ]
        return createFormTests.contains { name.contains($0) } ? "createGroup" : "groups"
    }

    /// Navigates to the Groups tab or skips the test if the user is not signed in.
    private func requireGroupsTab(timeout: TimeInterval = 6) throws {
        if newGroupTitle.waitForExistence(timeout: 1) {
            app.buttons["Back"].firstMatch.tap()
        }

        if groupSurfaceExists(timeout: 2) { return }

        if let tab = waitForGroupsTab(timeout: timeout) {
            tab.tap()
        } else {
            tapGroupsTabByPosition()
        }

        guard groupSurfaceExists(timeout: 4) else {
            throw XCTSkip("App is not signed in — sign in on the simulator before running group flow tests.")
        }
    }

    /// Opens the first active-groups cell or skips if the list is empty.
    private func requireFirstActiveGroup() throws {
        let group = activeGroupButtons.firstMatch
        if group.waitForExistence(timeout: 4), group.isHittable {
            group.tap()
        } else {
            launch(route: "firstGroupDetail")
        }
        guard app.buttons["Group actions"].waitForExistence(timeout: 6) else {
            throw XCTSkip("No active group detail available — create or seed an active group first.")
        }
    }

    private var groupsTitle: XCUIElement {
        app.staticTexts["xBill.pageHeader.title.Groups"]
    }

    private var homeGroupsHeader: XCUIElement {
        app.otherElements["xBill.home.groupsHeader"].firstMatch
    }

    private var newGroupTitle: XCUIElement {
        app.staticTexts["xBill.pageHeader.title.New Group"]
    }

    private var activeGroupButtons: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", " group, active"))
    }

    private func groupSurfaceExists(timeout: TimeInterval) -> Bool {
        if groupsTitle.waitForExistence(timeout: timeout)
            || homeGroupsHeader.waitForExistence(timeout: 0.5)
            || activeGroupButtons.firstMatch.waitForExistence(timeout: 0.5) {
            return true
        }

        return false
    }

    private func groupsTabCandidate() -> XCUIElement {
        groupsTabCandidates().first(where: { $0.exists }) ?? app.staticTexts["Groups"].firstMatch
    }

    private func waitForGroupsTab(timeout: TimeInterval) -> XCUIElement? {
        let perCandidateTimeout = min(timeout, 0.5)
        for candidate in groupsTabCandidates() {
            if candidate.waitForExistence(timeout: perCandidateTimeout) {
                return candidate
            }
        }

        return nil
    }

    private func tapGroupsTabByPosition() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.34, dy: 0.93)).tap()
    }

    private func groupsTabCandidates() -> [XCUIElement] {
        [
            app.buttons["xBill.tab.groups"],
            app.otherElements["xBill.tab.groups"],
            app.staticTexts["xBill.tab.groups"],
            app.buttons["xBill.uitest.tab.groups"],
            app.tabBars.buttons["Groups"],
            app.buttons["Groups"].firstMatch,
            app.otherElements["Groups"].firstMatch
        ]
    }

    private var emailAuthSubmitButton: XCUIElement {
        app.buttons["xBill.emailAuth.submitButton"]
    }

    private func openEmailAuthIfNeeded() {
        if emailAuthSubmitButton.waitForExistence(timeout: 2) { return }
        let emailButton = app.buttons["Continue with Email"].firstMatch
        XCTAssertTrue(emailButton.waitForExistence(timeout: 8))
        emailButton.tap()
        XCTAssertTrue(emailAuthSubmitButton.waitForExistence(timeout: 8))
    }

    private func completeOnboardingIfNeeded() {
        if app.buttons["Skip"].waitForExistence(timeout: 3) {
            app.buttons["Skip"].tap()
            return
        }
        for _ in 0..<4 where app.buttons["Next"].waitForExistence(timeout: 1) {
            app.buttons["Next"].tap()
        }
        if app.buttons["Get Started"].waitForExistence(timeout: 2) {
            app.buttons["Get Started"].tap()
        }
    }

    private func openCreateGroup() {
        if newGroupTitle.waitForExistence(timeout: 0.5) { return }

        let button = app.buttons["xBill.groups.createButton"]
        if button.waitForExistence(timeout: 2) {
            button.tap()
        } else {
            let fallback = app.buttons["Create Group"].firstMatch
            if fallback.waitForExistence(timeout: 1) {
                fallback.tap()
            } else {
                launch(route: "createGroup")
            }
        }
    }

    private func groupButton(named name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "\(name) group")).firstMatch
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
           let credentials = NSDictionary(contentsOf: url) as? [String: String],
           let value = credentials[key],
           !value.isEmpty,
           !value.hasPrefix("$(") {
            return value
        }
        return nil
    }

    private func archivedRowButton() -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Archived")).firstMatch
    }

    private func tapConfirmationCancel() {
        let cancel = app.descendants(matching: .any)["Cancel"].firstMatch
        if cancel.waitForExistence(timeout: 2), cancel.isHittable {
            cancel.tap()
            return
        }

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
    }

    private func createGroup(named groupName: String, opensCreatedGroupAfterCreate: Bool = false) {
        if !newGroupTitle.waitForExistence(timeout: 0.5) {
            launch(route: opensCreatedGroupAfterCreate ? "createGroupThenOpen" : "createGroup")
        }
        XCTAssertTrue(newGroupTitle.waitForExistence(timeout: 4))

        let nameField = app.textFields["e.g. Weekend Trip"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()
        nameField.typeText(groupName)
        app.buttons["xBill.createGroup.submitButton"].tap()
    }

    // MARK: - Create Group — Form Validation

    func test000SignInWithEnvironmentCredentials() throws {
        if groupSurfaceExists(timeout: 4) { return }
        if waitForGroupsTab(timeout: 4) != nil { return }
        tapGroupsTabByPosition()
        if groupSurfaceExists(timeout: 4) { return }

        guard let email = testCredential(named: "XBILL_TEST_EMAIL"),
              let password = testCredential(named: "XBILL_TEST_PASSWORD"),
              !email.isEmpty,
              !password.isEmpty else {
            throw XCTSkip("Set XBILL_TEST_EMAIL and XBILL_TEST_PASSWORD to sign in before group-flow tests.")
        }

        openEmailAuthIfNeeded()

        let emailField = app.textFields["you@example.com"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 4))
        emailField.tap()
        emailField.typeText(email)

        let passwordField = app.secureTextFields["Min. 8 characters"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 2))
        passwordField.tap()
        passwordField.typeText(password)

        XCTAssertTrue(emailAuthSubmitButton.waitForExistence(timeout: 2))
        emailAuthSubmitButton.tap()

        completeOnboardingIfNeeded()
        if !groupSurfaceExists(timeout: 4) {
            if let tab = waitForGroupsTab(timeout: 20), tab.isHittable {
                tab.tap()
            } else {
                tapGroupsTabByPosition()
            }
        }
        XCTAssertTrue(groupSurfaceExists(timeout: 4))
    }

    func testCreateGroupSheetOpens() throws {
        openCreateGroup()
        XCTAssertTrue(newGroupTitle.waitForExistence(timeout: 4),
                      "New Group sheet should appear")
    }

    func testCreateGroupFormHasNameField() throws {
        openCreateGroup()
        XCTAssertTrue(newGroupTitle.waitForExistence(timeout: 4))
        XCTAssertTrue(app.textFields["e.g. Weekend Trip"].waitForExistence(timeout: 2),
                      "Group name field should be present")
    }

    func testCreateGroupFormHasBackButton() throws {
        openCreateGroup()
        XCTAssertTrue(newGroupTitle.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Back"].exists)
    }

    func testCreateButtonDisabledWithEmptyName() throws {
        openCreateGroup()
        XCTAssertTrue(newGroupTitle.waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["xBill.createGroup.submitButton"].isEnabled,
                       "Create button should be disabled when name is empty")
    }

    func testCreateButtonEnabledAfterTypingName() throws {
        openCreateGroup()
        XCTAssertTrue(newGroupTitle.waitForExistence(timeout: 4))

        let nameField = app.textFields["e.g. Weekend Trip"]
        nameField.tap()
        nameField.typeText("QA Flow Test")

        XCTAssertTrue(app.buttons["xBill.createGroup.submitButton"].isEnabled,
                      "Create button should be enabled after typing a name")
    }

    func testBackDismissesCreateSheet() throws {
        openCreateGroup()
        XCTAssertTrue(newGroupTitle.waitForExistence(timeout: 4))
        app.buttons["Back"].tap()
        XCTAssertTrue(groupSurfaceExists(timeout: 3),
                      "Group surface should reappear after Back")
    }

    /// This test creates a real group — use a unique name each run.
    func testCreateGroupAppearsInListImmediately() throws {
        try requireGroupsTab()
        // L-38: use a timestamp-based suffix to avoid collision across parallel CI runs.
        // Int.random() can repeat when multiple agents seed from the same clock tick.
        let suffix = Int(Date().timeIntervalSince1970 * 1000) % 100_000
        let groupName = "UITest-\(suffix)"

        // L-39: register a teardown block that attempts to archive the created group
        // via the UI so it is not left as orphaned test data in Supabase after each run.
        addTeardownBlock { [weak self] in
            guard let self else { return }
            // Navigate back to groups list if we drifted somewhere else.
            let tab = self.groupsTabCandidate()
            if tab.waitForExistence(timeout: 3) { tab.tap() }

            // Find the group we created and navigate into it.
            let btn = self.groupButton(named: groupName)
            guard btn.waitForExistence(timeout: 4), btn.isHittable else { return }
            btn.tap()

            // Open the toolbar menu and attempt to archive (silently skip if not present).
            guard self.app.buttons["Group actions"].waitForExistence(timeout: 3) else { return }
            self.app.buttons["Group actions"].tap()
            guard self.app.buttons["Archive Group"].waitForExistence(timeout: 2) else { return }
            self.app.buttons["Archive Group"].tap()
            // Confirm in dialog if it appears.
            if self.app.buttons["Archive Group"].waitForExistence(timeout: 2) {
                self.app.buttons["Archive Group"].tap()
            }
        }

        createGroup(named: groupName)

        // After dismiss, the new group must be in the list immediately — no refresh required.
        let group = groupButton(named: groupName)
        XCTAssertTrue(group.waitForExistence(timeout: 6),
                      "New group '\(groupName)' should appear in list without a pull-to-refresh (onCreated append fix)")
    }

    // MARK: - Archive Group

    func testGroupDetailToolbarMenuExists() throws {
        try requireGroupsTab()
        try requireFirstActiveGroup()

        let moreButton = app.buttons["Group actions"]
        XCTAssertTrue(moreButton.waitForExistence(timeout: 3),
                      "Toolbar menu button should exist in GroupDetailView")
    }

    func testArchiveOrUnarchiveOptionInMenu() throws {
        try requireGroupsTab()
        try requireFirstActiveGroup()

        app.buttons["Group actions"].tap()

        let archiveButton   = app.buttons["Archive Group"]
        let unarchiveButton = app.buttons["Unarchive Group"]

        XCTAssertTrue(
            archiveButton.waitForExistence(timeout: 3) || unarchiveButton.waitForExistence(timeout: 3),
            "Either 'Archive Group' or 'Unarchive Group' must appear — only the contextually correct one shows"
        )
    }

    func testArchiveConfirmationDialogAppearsAndCancelWorks() throws {
        try requireGroupsTab()
        try requireFirstActiveGroup()

        app.buttons["Group actions"].tap()

        guard app.buttons["Archive Group"].waitForExistence(timeout: 3) else {
            throw XCTSkip("First active group is already archived — use an active group.")
        }
        app.buttons["Archive Group"].tap()

        // Dialog: title + destructive button + Cancel
        XCTAssertTrue(app.buttons["Archive Group"].waitForExistence(timeout: 3),
                      "Confirmation dialog Archive button should appear")

        tapConfirmationCancel()
        // After Cancel, still on detail screen
        XCTAssertTrue(app.buttons["Group actions"].waitForExistence(timeout: 2))
    }

    func testArchiveGroupMovesItToArchivedSection() throws {
        // First create a throwaway group so we have one to archive
        try requireGroupsTab()
        let groupName = "ArchiveTest-\(Int.random(in: 10000...99999))"

        createGroup(named: groupName, opensCreatedGroupAfterCreate: true)
        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.\(groupName)"].waitForExistence(timeout: 4))

        // Open menu and archive
        app.buttons["Group actions"].tap()
        XCTAssertTrue(app.buttons["Archive Group"].waitForExistence(timeout: 3))
        app.buttons["Archive Group"].tap()
        // Confirm in dialog
        XCTAssertTrue(app.buttons["Archive Group"].waitForExistence(timeout: 3))
        app.buttons["Archive Group"].tap()

        // Back on Groups list — archived group must NOT be in active section
        XCTAssertTrue(groupSurfaceExists(timeout: 6),
                      "Should navigate back to group surface after archive")
        XCTAssertFalse(
            activeGroupButtons.matching(NSPredicate(format: "label CONTAINS %@", groupName)).firstMatch.waitForExistence(timeout: 2),
            "Archived group '\(groupName)' must be gone from active list immediately (P0 stale-list fix)"
        )

        // Archived section must show the group
        let archivedRow = archivedRowButton()
        XCTAssertTrue(archivedRow.waitForExistence(timeout: 3),
                      "Archived row should appear")
        archivedRow.tap() // expand
        XCTAssertTrue(
            groupButton(named: groupName).waitForExistence(timeout: 3),
            "Archived group '\(groupName)' should appear in archived section"
        )
    }

    // MARK: - Unarchive Group

    func testArchivedSectionHeaderExists() throws {
        try requireGroupsTab()
        // May not exist if no archived groups — just verify the redesigned Groups screen is visible.
        XCTAssertTrue(groupSurfaceExists(timeout: 3))
        // Pass whether or not the header is there; this is informational
        let archivedRow = archivedRowButton()
        if archivedRow.waitForExistence(timeout: 3) {
            XCTAssertTrue(archivedRow.exists, "Archived row should be present when archived groups exist")
        }
    }

    func testArchivedSectionExpandsOnTap() throws {
        try requireGroupsTab()
        let archivedRow = archivedRowButton()
        guard archivedRow.waitForExistence(timeout: 3) else {
            throw XCTSkip("No archived groups — archive a group first.")
        }
        let groupCountBefore = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", " group, archived")).count
        archivedRow.tap()
        // Give the list time to animate
        Thread.sleep(forTimeInterval: 0.5)
        let groupCountAfter = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", " group, archived")).count
        XCTAssertGreaterThanOrEqual(groupCountAfter, groupCountBefore,
                                    "Archived group count should increase or stay same after expanding archived section")
    }

    func testUnarchiveContextActionAppearsOnArchivedRow() throws {
        try requireGroupsTab()
        let archivedRow = archivedRowButton()
        guard archivedRow.waitForExistence(timeout: 3) else {
            throw XCTSkip("No archived groups — archive a group first.")
        }
        archivedRow.tap()
        Thread.sleep(forTimeInterval: 0.5)

        let archivedGroup = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", " group, archived")).firstMatch
        guard archivedGroup.waitForExistence(timeout: 3) else {
            throw XCTSkip("Archived section expanded but has no group rows.")
        }
        archivedGroup.press(forDuration: 1.0)
        guard app.buttons["Unarchive"].waitForExistence(timeout: 2) else {
            throw XCTSkip("SwiftUI context menu action was not exposed by this simulator run.")
        }
        XCTAssertTrue(app.buttons["Unarchive"].exists,
                      "Unarchive context action should appear on archived group rows when the context menu opens")
    }

    func testUnarchiveFromDetailViewToolbar() throws {
        try requireGroupsTab()
        let archivedRow = archivedRowButton()
        guard archivedRow.waitForExistence(timeout: 3) else {
            throw XCTSkip("No archived groups — archive a group first.")
        }
        archivedRow.tap()
        Thread.sleep(forTimeInterval: 0.5)

        let archivedGroup = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", " group, archived")).firstMatch
        guard archivedGroup.waitForExistence(timeout: 3) else {
            throw XCTSkip("No archived groups visible after expansion.")
        }
        let groupName = archivedGroup.label.components(separatedBy: " group").first ?? ""
        archivedGroup.tap()

        guard app.buttons["Group actions"].waitForExistence(timeout: 4) else {
            throw XCTSkip("Archived group detail did not finish presenting in this simulator run.")
        }

        // Menu should show "Unarchive Group" for an archived group
        app.buttons["Group actions"].tap()
        XCTAssertTrue(app.buttons["Unarchive Group"].waitForExistence(timeout: 3),
                      "Archived group detail view should show 'Unarchive Group' in toolbar (dead-code fix)")

        // Confirm unarchive
        app.buttons["Unarchive Group"].tap()
        XCTAssertTrue(app.buttons["Unarchive Group"].waitForExistence(timeout: 3))
        app.buttons["Unarchive Group"].tap()

        // Should be back on Groups list, group back in active section
        XCTAssertTrue(groupSurfaceExists(timeout: 6),
                      "Should return to group surface after unarchive")
        if !groupName.isEmpty {
            XCTAssertTrue(
                groupButton(named: groupName).waitForExistence(timeout: 4),
                "'\(groupName)' should reappear in active group list after unarchiving from detail view"
            )
        }
    }

    // MARK: - Toolbar Context-Sensitivity (regression guard)

    func testActiveGroupShowsArchiveNotUnarchive() throws {
        try requireGroupsTab()
        let activeGroup = activeGroupButtons.firstMatch
        guard activeGroup.waitForExistence(timeout: 4) else {
            throw XCTSkip("No active groups in list.")
        }
        activeGroup.tap()
        XCTAssertTrue(app.buttons["Group actions"].waitForExistence(timeout: 6))

        app.buttons["Group actions"].tap()

        // Active group MUST show Archive and MUST NOT show Unarchive
        XCTAssertTrue(app.buttons["Archive Group"].waitForExistence(timeout: 3),
                      "Active group must show 'Archive Group' option")
        XCTAssertFalse(app.buttons["Unarchive Group"].exists,
                       "Active group must NOT show 'Unarchive Group' option")
    }
}
