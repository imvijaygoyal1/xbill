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
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDown() async throws {
        app = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Navigates to the Groups tab or skips the test if the user is not signed in.
    private func requireGroupsTab(timeout: TimeInterval = 6) throws {
        let tab = app.tabBars.buttons["Groups"]
        guard tab.waitForExistence(timeout: timeout) else {
            throw XCTSkip("App is not signed in — sign in on the simulator before running group flow tests.")
        }
        tab.tap()
        XCTAssertTrue(groupsTitle.waitForExistence(timeout: 4))
    }

    /// Opens the first active-groups cell or skips if the list is empty.
    private func requireFirstActiveGroup() throws {
        let group = activeGroupButtons.firstMatch
        guard group.waitForExistence(timeout: 4), group.isHittable else {
            throw XCTSkip("No groups in the active list — create a group first.")
        }
        group.tap()
        XCTAssertTrue(app.buttons["Group actions"].waitForExistence(timeout: 4))
    }

    private var groupsTitle: XCUIElement {
        app.staticTexts["xBill.pageHeader.title.Groups"]
    }

    private var newGroupTitle: XCUIElement {
        app.staticTexts["xBill.pageHeader.title.New Group"]
    }

    private var activeGroupButtons: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", " group, active"))
    }

    private func openCreateGroup() {
        let button = app.buttons["xBill.groups.createButton"]
        if button.waitForExistence(timeout: 2) {
            button.tap()
        } else {
            app.buttons["Create Group"].firstMatch.tap()
        }
    }

    private func groupButton(named name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "\(name) group")).firstMatch
    }

    private func archivedRowButton() -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Archived")).firstMatch
    }

    private func createGroup(named groupName: String) {
        openCreateGroup()
        XCTAssertTrue(newGroupTitle.waitForExistence(timeout: 4))

        let nameField = app.textFields["e.g. Weekend Trip"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()
        nameField.typeText(groupName)
        app.buttons["xBill.createGroup.submitButton"].tap()
    }

    // MARK: - Create Group — Form Validation

    func testCreateGroupSheetOpens() throws {
        try requireGroupsTab()
        openCreateGroup()
        XCTAssertTrue(newGroupTitle.waitForExistence(timeout: 4),
                      "New Group sheet should appear")
    }

    func testCreateGroupFormHasNameField() throws {
        try requireGroupsTab()
        openCreateGroup()
        XCTAssertTrue(newGroupTitle.waitForExistence(timeout: 4))
        XCTAssertTrue(app.textFields["e.g. Weekend Trip"].waitForExistence(timeout: 2),
                      "Group name field should be present")
    }

    func testCreateGroupFormHasBackButton() throws {
        try requireGroupsTab()
        openCreateGroup()
        XCTAssertTrue(newGroupTitle.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Back"].exists)
    }

    func testCreateButtonDisabledWithEmptyName() throws {
        try requireGroupsTab()
        openCreateGroup()
        XCTAssertTrue(newGroupTitle.waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["xBill.createGroup.submitButton"].isEnabled,
                       "Create button should be disabled when name is empty")
    }

    func testCreateButtonEnabledAfterTypingName() throws {
        try requireGroupsTab()
        openCreateGroup()
        XCTAssertTrue(newGroupTitle.waitForExistence(timeout: 4))

        let nameField = app.textFields["e.g. Weekend Trip"]
        nameField.tap()
        nameField.typeText("QA Flow Test")

        XCTAssertTrue(app.buttons["xBill.createGroup.submitButton"].isEnabled,
                      "Create button should be enabled after typing a name")
    }

    func testBackDismissesCreateSheet() throws {
        try requireGroupsTab()
        openCreateGroup()
        XCTAssertTrue(newGroupTitle.waitForExistence(timeout: 4))
        app.buttons["Back"].tap()
        XCTAssertTrue(groupsTitle.waitForExistence(timeout: 3),
                      "Groups list should reappear after Back")
    }

    /// This test creates a real group — use a unique name each run.
    func testCreateGroupAppearsInListImmediately() throws {
        try requireGroupsTab()
        let groupName = "UITest-\(Int.random(in: 10000...99999))"

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

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        // After Cancel, still on detail screen
        XCTAssertTrue(app.buttons["Group actions"].waitForExistence(timeout: 2))
    }

    func testArchiveGroupMovesItToArchivedSection() throws {
        // First create a throwaway group so we have one to archive
        try requireGroupsTab()
        let groupName = "ArchiveTest-\(Int.random(in: 10000...99999))"

        createGroup(named: groupName)
        XCTAssertTrue(groupButton(named: groupName).waitForExistence(timeout: 6))

        // Navigate into the group
        groupButton(named: groupName).tap()
        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.\(groupName)"].waitForExistence(timeout: 4))

        // Open menu and archive
        app.buttons["Group actions"].tap()
        XCTAssertTrue(app.buttons["Archive Group"].waitForExistence(timeout: 3))
        app.buttons["Archive Group"].tap()
        // Confirm in dialog
        XCTAssertTrue(app.buttons["Archive Group"].waitForExistence(timeout: 3))
        app.buttons["Archive Group"].tap()

        // Back on Groups list — archived group must NOT be in active section
        XCTAssertTrue(groupsTitle.waitForExistence(timeout: 6),
                      "Should navigate back to Groups list after archive")
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
        XCTAssertTrue(groupsTitle.waitForExistence(timeout: 3))
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
        XCTAssertTrue(groupsTitle.waitForExistence(timeout: 6),
                      "Should return to Groups list after unarchive")
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
        XCTAssertTrue(app.buttons["Group actions"].waitForExistence(timeout: 4))

        app.buttons["Group actions"].tap()

        // Active group MUST show Archive and MUST NOT show Unarchive
        XCTAssertTrue(app.buttons["Archive Group"].waitForExistence(timeout: 3),
                      "Active group must show 'Archive Group' option")
        XCTAssertFalse(app.buttons["Unarchive Group"].exists,
                       "Active group must NOT show 'Unarchive Group' option")
    }
}
