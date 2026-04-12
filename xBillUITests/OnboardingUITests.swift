import XCTest

@MainActor
final class OnboardingUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-state"]
        app.launch()
    }

    override func tearDown() async throws {
        app = nil
        try await super.tearDown()
    }

    // MARK: - Auth Screen

    func testAuthScreenDisplayed() {
        let logo = app.images["xBill"]
        let emailButton = app.buttons["Continue with Email"]
        let appleButton = app.buttons["Continue with Apple"]

        XCTAssertTrue(emailButton.waitForExistence(timeout: 5))
        XCTAssertTrue(appleButton.exists)
        _ = logo
    }

    // MARK: - Email Sign Up Flow

    func testEmailSignUpFlow() throws {
        app.buttons["Continue with Email"].tap()

        // Verify sign-in screen
        XCTAssertTrue(app.navigationBars["Sign In"].waitForExistence(timeout: 3))

        // Switch to sign-up
        app.buttons["No account? "].tap()
        XCTAssertTrue(app.navigationBars["Create Account"].waitForExistence(timeout: 2))

        // Fill in fields
        let nameField = app.textFields["Your name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()
        nameField.typeText("Test User")

        let emailField = app.textFields["you@example.com"]
        emailField.tap()
        emailField.typeText("test+\(Int.random(in: 1000...9999))@example.com")

        let passwordFields = app.secureTextFields.allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(passwordFields.count, 2)
        passwordFields[0].tap()
        passwordFields[0].typeText("TestPass123!")
        passwordFields[1].tap()
        passwordFields[1].typeText("TestPass123!")

        // Submit — in UI tests, we verify the button is enabled and tappable
        let createButton = app.buttons["Create Account"]
        XCTAssertTrue(createButton.isEnabled)
    }

    // MARK: - Email Sign In Validation

    func testSignInValidatesEmail() {
        app.buttons["Continue with Email"].tap()

        let signInButton = app.buttons["Sign In"]
        XCTAssertTrue(signInButton.waitForExistence(timeout: 3))

        // Initially disabled (no email/password)
        XCTAssertFalse(signInButton.isEnabled)

        // Enter invalid email
        let emailField = app.textFields["you@example.com"]
        emailField.tap()
        emailField.typeText("notanemail")
        XCTAssertFalse(signInButton.isEnabled)

        // Enter valid email, still no password
        emailField.clearText()
        emailField.typeText("valid@email.com")
        XCTAssertFalse(signInButton.isEnabled)
    }

    // MARK: - Toggle Between Sign In and Sign Up

    func testToggleBetweenSignInAndSignUp() {
        app.buttons["Continue with Email"].tap()

        XCTAssertTrue(app.navigationBars["Sign In"].waitForExistence(timeout: 3))
        app.buttons["No account? "].tap()
        XCTAssertTrue(app.navigationBars["Create Account"].waitForExistence(timeout: 2))
        app.buttons["Already have an account? "].tap()
        XCTAssertTrue(app.navigationBars["Sign In"].waitForExistence(timeout: 2))
    }

    // MARK: - Password Reset

    func testForgotPasswordVisible() {
        app.buttons["Continue with Email"].tap()
        XCTAssertTrue(app.buttons["Forgot password?"].waitForExistence(timeout: 3))
    }
}

// MARK: - XCUIElement helpers

private extension XCUIElement {
    func clearText() {
        guard let stringValue = value as? String else { return }
        tap()
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
        typeText(deleteString)
    }
}
