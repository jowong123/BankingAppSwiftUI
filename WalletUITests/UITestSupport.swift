import XCTest

extension XCTestCase {
    /// Launches against the in-app mock (SPEC section 8), in English so spoken labels are stable.
    @MainActor
    func launchApp(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            ["-uiTesting", "-mockServer", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extraArguments
        app.launch()
        return app
    }

    /// Signs in and creates PIN 123456, ending on the accounts list.
    @MainActor
    func signIn(_ app: XCUIApplication, password: String = "pw") {
        let email = app.textFields["auth.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        email.tap()
        email.typeText("demo@wallet.test")
        let passwordField = app.secureTextFields["auth.password"]
        passwordField.tap()
        passwordField.typeText(password)
        app.buttons["auth.submit"].tap()
        XCTAssertTrue(app.staticTexts["auth.createPIN.prompt"].waitForExistence(timeout: 10))
        enterPIN("123456", in: app)
        enterPIN("123456", in: app)
    }

    @MainActor
    func enterPIN(_ pin: String, in app: XCUIApplication) {
        for digit in pin {
            app.buttons[String(digit)].tap()
        }
    }
}
