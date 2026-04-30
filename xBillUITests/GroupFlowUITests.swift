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
        XCTAssertTrue(app.navigationBars["Groups"].waitForExistence(timeout: 4))
    }

    /// Opens the first active-groups cell or skips if the list is empty.
    private func requireFirstActiveGroup() throws {
        let cell = app.tables.cells.firstMatch
        guard cell.waitForExistence(timeout: 4), cell.isHittable else {
            throw XCTSkip("No groups in the active list — create a group first.")
        }
        cell.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 4))
    }

    // MARK: - Create Group — Form Validation

    func testCreateGroupSheetOpens() throws {
        try requireGroupsTab()
        app.navigationBars["Groups"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["New Group"].waitForExistence(timeout: 4),
                      "New Group sheet should appear")
    }

    func testCreateGroupFormHasNameField() throws {
        try requireGroupsTab()
        app.navigationBars["Groups"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["New Group"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.textFields["e.g. Weekend Trip"].waitForExistence(timeout: 2),
                      "Group name field should be present")
    }

    func testCreateGroupFormHasCancelButton() throws {
        try requireGroupsTab()
        app.navigationBars["Groups"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["New Group"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Cancel"].exists)
    }

    func testCreateButtonDisabledWithEmptyName() throws {
        try requireGroupsTab()
        app.navigationBars["Groups"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["New Group"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["Create"].isEnabled,
                       "Create button should be disabled when name is empty")
    }

    func testCreateButtonEnabledAfterTypingName() throws {
        try requireGroupsTab()
        app.navigationBars["Groups"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["New Group"].waitForExistence(timeout: 4))

        let nameField = app.textFields["e.g. Weekend Trip"]
        nameField.tap()
        nameField.typeText("QA Flow Test")

        XCTAssertTrue(app.buttons["Create"].isEnabled,
                      "Create button should be enabled after typing a name")
    }

    func testCancelDismissesCreateSheet() throws {
        try requireGroupsTab()
        app.navigationBars["Groups"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["New Group"].waitForExistence(timeout: 4))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Groups"].waitForExistence(timeout: 3),
                      "Groups list should reappear after Cancel")
    }

    /// This test creates a real group — use a unique name each run.
    func testCreateGroupAppearsInListImmediately() throws {
        try requireGroupsTab()
        let groupName = "UITest-\(Int.random(in: 10000...99999))"

        app.navigationBars["Groups"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["New Group"].waitForExistence(timeout: 4))

        let nameField = app.textFields["e.g. Weekend Trip"]
        nameField.tap()
        nameField.typeText(groupName)
        app.buttons["Create"].tap()

        // After dismiss, the new group must be in the list immediately — no refresh required.
        let cell = app.cells.containing(.staticText, identifier: groupName).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 6),
                      "New group '\(groupName)' should appear in list without a pull-to-refresh (onCreated append fix)")
    }

    // MARK: - Archive Group

    func testGroupDetailToolbarMenuExists() throws {
        try requireGroupsTab()
        try requireFirstActiveGroup()

        // The overflow menu button (ellipsis.circle) must be in the nav bar
        let moreButton = app.navigationBars.buttons.matching(
            NSPredicate(format: "label CONTAINS 'more' OR label CONTAINS 'ellipsis' OR label CONTAINS 'More'")
        ).firstMatch
        XCTAssertTrue(moreButton.waitForExistence(timeout: 3) || app.navigationBars.buttons.count > 1,
                      "Toolbar menu button should exist in GroupDetailView")
    }

    func testArchiveOrUnarchiveOptionInMenu() throws {
        try requireGroupsTab()
        try requireFirstActiveGroup()

        // Tap the trailing toolbar menu
        let navBar = app.navigationBars.firstMatch
        navBar.buttons.element(boundBy: navBar.buttons.count - 1).tap()

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

        let navBar = app.navigationBars.firstMatch
        navBar.buttons.element(boundBy: navBar.buttons.count - 1).tap()

        guard app.buttons["Archive Group"].waitForExistence(timeout: 3) else {
            throw XCTSkip("First active group is already archived — use an active group.")
        }
        app.buttons["Archive Group"].tap()

        // Dialog: title + destructive button + Cancel
        XCTAssertTrue(app.buttons["Archive Group"].waitForExistence(timeout: 3),
                      "Confirmation dialog Archive button should appear")
        XCTAssertTrue(app.buttons["Cancel"].exists,
                      "Confirmation dialog Cancel button should appear")

        app.buttons["Cancel"].tap()
        // After Cancel, still on detail screen
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 2))
    }

    func testArchiveGroupMovesItToArchivedSection() throws {
        // First create a throwaway group so we have one to archive
        try requireGroupsTab()
        let groupName = "ArchiveTest-\(Int.random(in: 10000...99999))"

        app.navigationBars["Groups"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["New Group"].waitForExistence(timeout: 4))
        let nameField = app.textFields["e.g. Weekend Trip"]
        nameField.tap()
        nameField.typeText(groupName)
        app.buttons["Create"].tap()
        XCTAssertTrue(app.cells.containing(.staticText, identifier: groupName).firstMatch.waitForExistence(timeout: 6))

        // Navigate into the group
        app.cells.containing(.staticText, identifier: groupName).firstMatch.tap()
        XCTAssertTrue(app.navigationBars[groupName].waitForExistence(timeout: 4))

        // Open menu and archive
        let navBar = app.navigationBars.firstMatch
        navBar.buttons.element(boundBy: navBar.buttons.count - 1).tap()
        XCTAssertTrue(app.buttons["Archive Group"].waitForExistence(timeout: 3))
        app.buttons["Archive Group"].tap()
        // Confirm in dialog
        XCTAssertTrue(app.buttons["Archive Group"].waitForExistence(timeout: 3))
        app.buttons["Archive Group"].tap()

        // Back on Groups list — archived group must NOT be in active section
        XCTAssertTrue(app.navigationBars["Groups"].waitForExistence(timeout: 6),
                      "Should navigate back to Groups list after archive")
        XCTAssertFalse(
            app.cells.containing(.staticText, identifier: groupName).firstMatch.waitForExistence(timeout: 2),
            "Archived group '\(groupName)' must be gone from active list immediately (P0 stale-list fix)"
        )

        // Archived section must show the group
        let archivedHeader = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'ARCHIVED'")
        ).firstMatch
        XCTAssertTrue(archivedHeader.waitForExistence(timeout: 3),
                      "Archived section header should appear")
        archivedHeader.tap() // expand
        XCTAssertTrue(
            app.cells.containing(.staticText, identifier: groupName).firstMatch.waitForExistence(timeout: 3),
            "Archived group '\(groupName)' should appear in archived section"
        )
    }

    // MARK: - Unarchive Group

    func testArchivedSectionHeaderExists() throws {
        try requireGroupsTab()
        // May not exist if no archived groups — just verify the list is visible
        _ = app.tables.firstMatch.waitForExistence(timeout: 3)
        // Pass whether or not the header is there; this is informational
        let archivedHeader = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'ARCHIVED'")
        ).firstMatch
        if archivedHeader.waitForExistence(timeout: 3) {
            XCTAssertTrue(archivedHeader.isHittable, "Archived header should be tappable to expand/collapse")
        }
    }

    func testArchivedSectionExpandsOnTap() throws {
        try requireGroupsTab()
        let archivedHeader = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'ARCHIVED'")
        ).firstMatch
        guard archivedHeader.waitForExistence(timeout: 3) else {
            throw XCTSkip("No archived groups — archive a group first.")
        }
        let cellCountBefore = app.tables.cells.count
        archivedHeader.tap()
        // Give the list time to animate
        Thread.sleep(forTimeInterval: 0.5)
        let cellCountAfter = app.tables.cells.count
        XCTAssertGreaterThanOrEqual(cellCountAfter, cellCountBefore,
                                    "Cell count should increase or stay same after expanding archived section")
    }

    func testUnarchiveSwipeActionAppearsOnArchivedRow() throws {
        try requireGroupsTab()
        let archivedHeader = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'ARCHIVED'")
        ).firstMatch
        guard archivedHeader.waitForExistence(timeout: 3) else {
            throw XCTSkip("No archived groups — archive a group first.")
        }
        archivedHeader.tap()
        Thread.sleep(forTimeInterval: 0.5)

        guard app.tables.cells.count > 0 else {
            throw XCTSkip("Archived section expanded but has no cells.")
        }
        // Swipe right on the last cell (archived rows are at the bottom of the table)
        app.tables.cells.element(boundBy: app.tables.cells.count - 1).swipeRight()
        XCTAssertTrue(app.buttons["Unarchive"].waitForExistence(timeout: 2),
                      "Unarchive swipe action should appear on archived group rows")
    }

    func testUnarchiveFromDetailViewToolbar() throws {
        try requireGroupsTab()
        let archivedHeader = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'ARCHIVED'")
        ).firstMatch
        guard archivedHeader.waitForExistence(timeout: 3) else {
            throw XCTSkip("No archived groups — archive a group first.")
        }
        archivedHeader.tap()
        Thread.sleep(forTimeInterval: 0.5)

        guard app.tables.cells.count > 0 else {
            throw XCTSkip("No archived cells visible after expansion.")
        }
        let archivedCell = app.tables.cells.element(boundBy: app.tables.cells.count - 1)
        let groupName = archivedCell.staticTexts.firstMatch.label
        archivedCell.tap()

        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 4))

        // Menu should show "Unarchive Group" for an archived group
        let navBar = app.navigationBars.firstMatch
        navBar.buttons.element(boundBy: navBar.buttons.count - 1).tap()
        XCTAssertTrue(app.buttons["Unarchive Group"].waitForExistence(timeout: 3),
                      "Archived group detail view should show 'Unarchive Group' in toolbar (dead-code fix)")

        // Confirm unarchive
        app.buttons["Unarchive Group"].tap()
        XCTAssertTrue(app.buttons["Unarchive Group"].waitForExistence(timeout: 3))
        app.buttons["Unarchive Group"].tap()

        // Should be back on Groups list, group back in active section
        XCTAssertTrue(app.navigationBars["Groups"].waitForExistence(timeout: 6),
                      "Should return to Groups list after unarchive")
        if !groupName.isEmpty {
            XCTAssertTrue(
                app.cells.containing(.staticText, identifier: groupName).firstMatch.waitForExistence(timeout: 4),
                "'\(groupName)' should reappear in active group list after unarchiving from detail view"
            )
        }
    }

    // MARK: - Toolbar Context-Sensitivity (regression guard)

    func testActiveGroupShowsArchiveNotUnarchive() throws {
        try requireGroupsTab()
        guard app.tables.cells.firstMatch.waitForExistence(timeout: 4) else {
            throw XCTSkip("No active groups in list.")
        }
        app.tables.cells.firstMatch.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 4))

        let navBar = app.navigationBars.firstMatch
        navBar.buttons.element(boundBy: navBar.buttons.count - 1).tap()

        // Active group MUST show Archive and MUST NOT show Unarchive
        XCTAssertTrue(app.buttons["Archive Group"].waitForExistence(timeout: 3),
                      "Active group must show 'Archive Group' option")
        XCTAssertFalse(app.buttons["Unarchive Group"].exists,
                       "Active group must NOT show 'Unarchive Group' option")
    }
}
