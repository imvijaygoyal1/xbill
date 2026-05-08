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

// MARK: - Login Screen

    func testLoginEntryScreenDisplaysRedesignedContent() {
        XCTAssertTrue(app.staticTexts["xBill"].waitForExistence(timeout: 5))
        // L-37: use a resilient selector instead of hardcoded marketing copy
        // so the test does not break when copywriters update the subtitle text.
        XCTAssertTrue(app.scrollViews.firstMatch.exists || app.otherElements["xBill.splitBillIllustration"].exists,
                      "Login screen should contain a scroll view or the split-bill illustration")
        XCTAssertTrue(app.otherElements["xBill.splitBillIllustration"].exists)
        XCTAssertTrue(app.staticTexts["Welcome back"].exists)
        XCTAssertTrue(app.staticTexts["Sign in to split expenses with your groups and friends."].exists)

        let emailButton = app.buttons["Continue with Email"]
        let appleButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Apple'")
        ).firstMatch

        XCTAssertTrue(emailButton.exists)
        XCTAssertTrue(emailButton.isHittable)
        XCTAssertTrue(appleButton.exists)
        XCTAssertTrue(app.buttons["Terms of Service"].exists)
        XCTAssertTrue(app.buttons["Privacy Policy"].exists)
    }

    func testLegalLinksAreAccessibleFromLoginScreen() {
        XCTAssertTrue(app.buttons["Terms of Service"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Terms of Service"].isHittable)
        XCTAssertTrue(app.buttons["Privacy Policy"].exists)
        XCTAssertTrue(app.buttons["Privacy Policy"].isHittable)
    }

    // MARK: - Email Sign Up Flow

    func testEmailSignUpFlow() throws {
        app.buttons["Continue with Email"].tap()

        // Verify sign-in screen
        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.Sign In"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["xBill.walletIllustration"].exists)
        XCTAssertTrue(app.staticTexts["Sign in with email"].exists)
        XCTAssertTrue(app.staticTexts["Enter your xBill email and password."].exists)

        // Switch to sign-up
        signUpToggle.tap()
        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.Create Account"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Create your account"].exists)

        // Fill in fields
        let nameField = app.textFields["Your name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()
        nameField.typeText("Test User")

        let emailField = app.textFields["you@example.com"]
        emailField.tap()
        emailField.typeText("test\(Int.random(in: 1000...9999))@example.com")

        // M-60: access password fields by placeholder text instead of positional index,
        // so the test is robust against field-order changes in the view hierarchy.
        let passwordField = app.secureTextFields["Password"]
        let confirmPasswordField = app.secureTextFields["Confirm Password"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 2))
        XCTAssertTrue(confirmPasswordField.waitForExistence(timeout: 2))
        passwordField.tap()
        passwordField.typeText("TestPass123!")
        confirmPasswordField.tap()
        confirmPasswordField.typeText("TestPass123!")

        // Submit — this test stops before network submission.
        let createButton = app.buttons["Create Account"]
        XCTAssertTrue(createButton.exists)
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

        // M-61: verify button becomes enabled once a password is also provided
        let passwordField = app.secureTextFields["Password"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 2))
        passwordField.tap()
        passwordField.typeText("TestPass123!")
        XCTAssertTrue(signInButton.firstMatch.isEnabled, "Sign In button should be enabled with valid credentials")
    }

    // MARK: - Toggle Between Sign In and Sign Up

    func testToggleBetweenSignInAndSignUp() {
        app.buttons["Continue with Email"].tap()

        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.Sign In"].waitForExistence(timeout: 3))
        signUpToggle.tap()
        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.Create Account"].waitForExistence(timeout: 2))
        signInToggle.tap()
        XCTAssertTrue(app.staticTexts["xBill.pageHeader.title.Sign In"].waitForExistence(timeout: 2))
    }

    // MARK: - Password Reset

    func testForgotPasswordVisible() {
        app.buttons["Continue with Email"].tap()
        XCTAssertTrue(app.buttons["Forgot password?"].waitForExistence(timeout: 3))
    }
}

// MARK: - XCUIElement helpers

private extension OnboardingUITests {
    var signUpToggle: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Create one'")).firstMatch
    }

    var signInToggle: XCUIElement {
        // L-40: the old predicate `label CONTAINS[c] 'Sign In'` matched both the
        // toggle link and the primary "Sign In" submit button, risking a tap on the
        // wrong element.  Prefer the exact toggle label; fall back to a predicate that
        // excludes the submit button (which uses the exact label "Sign In").
        let exactToggle = app.buttons["Already have an account? Sign in"]
        if exactToggle.exists { return exactToggle }
        return app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Sign In' AND NOT label == 'Sign In'")
        ).firstMatch
    }
}

private extension XCUIElement {
    func clearText() {
        guard let stringValue = value as? String else { return }
        tap()
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
        typeText(deleteString)
    }
}
