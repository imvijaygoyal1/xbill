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

    func testCreateGroupValidationRegression() throws {
        try signInIfNeeded()
        try requireGroupsSurface()
        try openCreateGroupForm()

        let submitButton = app.buttons["xBill.createGroup.submitButton"]
        XCTAssertTrue(submitButton.waitForExistence(timeout: 3), "Create button should exist.")
        XCTAssertFalse(submitButton.isEnabled, "Create button should be disabled before a group name is entered.")

        let nameField = app.textFields["e.g. Weekend Trip"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3), "New group name field should be visible.")
        nameField.tap()
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
        titleField.tap()
        titleField.typeText("Validation expense \(uniqueSuffix())")
        XCTAssertFalse(saveButton.isEnabled, "Save Expense should remain disabled without an amount.")

        let amountField = app.textFields["xBill.addExpense.amountField"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 4), "Amount field should be visible.")
        amountField.tap()
        amountField.typeText("12.34")
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
        commentField.tap()
        commentField.typeText(commentText)
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
        venmoField.tap()
        venmoField.typeText("bad")
        XCTAssertTrue(app.staticTexts["Venmo handles should start with @."].waitForExistence(timeout: 4), "Invalid Venmo handle should show validation.")
        dismissKeyboardIfNeeded()

        let signOut = app.buttons["Sign Out"].firstMatch
        scrollToElement(signOut)
        XCTAssertTrue(signOut.waitForExistence(timeout: 6), "Sign Out row should be available.")
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
        search.tap()
        search.typeText("nobody-\(uniqueSuffix())@example.invalid")

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
        emailField.tap()
        emailField.typeText("invalid-email")

        let passwordField = app.secureTextFields["xBill.emailAuth.passwordField"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 4), "Password field should be visible.")
        passwordField.tap()
        passwordField.typeText("short")
        XCTAssertFalse(submitButton.isEnabled, "Sign In should remain disabled for invalid email and short password.")

        app.buttons["xBill.emailAuth.forgotPasswordButton"].tap()
        XCTAssertTrue(app.staticTexts["Reset your password"].waitForExistence(timeout: 6), "Forgot Password sheet should open.")
        dismissSheetIfPossible()

        app.buttons["xBill.emailAuth.toggleModeButton"].tap()
        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.Create Account"].waitForExistence(timeout: 6), "Create Account mode should open.")

        let confirmField = app.secureTextFields["xBill.emailAuth.confirmPasswordField"]
        XCTAssertTrue(confirmField.waitForExistence(timeout: 4), "Confirm password field should be visible in sign-up mode.")
        confirmField.tap()
        confirmField.typeText("different-password")
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

        launchSignedOut()

        guard let email = testCredential(named: "XBILL_TEST_EMAIL"),
              let password = testCredential(named: "XBILL_TEST_PASSWORD") else {
            throw XCTSkip("Set XBILL_TEST_EMAIL and XBILL_TEST_PASSWORD, or provide xBillUITests/UITestCredentials.plist.")
        }

        let emailButton = app.buttons["Continue with Email"].firstMatch
        if emailButton.waitForExistence(timeout: 8) {
            emailButton.tap()
        }

        if app.staticTexts["xBill.pageHeader.title.Create Account"].waitForExistence(timeout: 1) {
            app.buttons["xBill.emailAuth.toggleModeButton"].tap()
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

        submitButton.tap()
        completeOnboardingIfNeeded()
        dismissNotificationPromptIfNeeded()

        if !groupSurfaceExists(timeout: 8) {
            launch(route: "groups")
            completeOnboardingIfNeeded()
            dismissNotificationPromptIfNeeded()
            tapGroupsTabIfPossible()
        }
        XCTAssertTrue(groupSurfaceExists(timeout: 8), "Signed-in Groups surface should load.")
    }

    private func completeOnboardingIfNeeded() {
        let skip = app.buttons["Skip"].firstMatch
        if skip.waitForExistence(timeout: 3) {
            skip.tap()
            return
        }
        let next = app.buttons["Next"].firstMatch
        for _ in 0..<4 where next.waitForExistence(timeout: 1) {
            next.tap()
        }
        let getStarted = app.buttons["Get Started"].firstMatch
        if getStarted.waitForExistence(timeout: 2) {
            getStarted.tap()
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
           let credentials = NSDictionary(contentsOf: url) as? [String: String],
           let value = credentials[key],
           !value.isEmpty,
           !value.hasPrefix("$(") {
            return value
        }
        return nil
    }

    private func dismissNotificationPromptIfNeeded() {
        let notNow = app.buttons["Not Now"].firstMatch
        if notNow.waitForExistence(timeout: 2) {
            notNow.tap()
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

    private func clearAndType(_ text: String, into element: XCUIElement) {
        element.tap()
        element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 80))
        element.typeText(text)
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
            if candidate.isHittable {
                candidate.tap()
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
        nameField.tap()
        nameField.typeText(groupName)
        app.buttons["xBill.createGroup.submitButton"].tap()

        XCTAssertTrue(activeGroupButton(named: groupName).waitForExistence(timeout: 8), "Created group should appear in Groups list.")
    }

    private func openGroup(named groupName: String) throws {
        let group = activeGroupButton(named: groupName)
        XCTAssertTrue(group.waitForExistence(timeout: 8), "Group row should be visible before opening detail.")
        group.tap()
        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.\(groupName)"].waitForExistence(timeout: 8), "Group detail should open.")
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

    private func searchGroups(_ text: String) {
        for _ in 0..<3 {
            let searchField = groupsSearchField()
            if searchField.waitForExistence(timeout: 2) {
                searchField.tap()
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
            || activeGroupButtons.firstMatch.waitForExistence(timeout: 0.5)
    }

    private func tapGroupsTabIfPossible() {
        for candidate in [
            app.buttons["xBill.tab.groups"],
            app.otherElements["xBill.tab.groups"],
            app.staticTexts["xBill.tab.groups"],
            app.buttons["xBill.uitest.tab.groups"],
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
        titleField.tap()
        titleField.typeText(title)

        let amountField = app.textFields["xBill.addExpense.amountField"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 4), "Amount field should be visible.")
        amountField.tap()
        amountField.typeText(amount)
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
