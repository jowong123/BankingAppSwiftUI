import XCTest

/// Against the real sandbox backend, not the mock. Skipped unless the credentials are passed
/// in the environment, so none are in source. Typed text is recorded in the `.xcresult`, so
/// use only the public sandbox user and keep this test out of CI:
///
///     cd backend && swift run WalletBackend serve
///     TEST_RUNNER_WALLET_E2E_EMAIL=... TEST_RUNNER_WALLET_E2E_PASSWORD=... xcodebuild test \
///       -only-testing:WalletUITests/EndToEndUITests ...
final class EndToEndUITests: XCTestCase {
    @MainActor
    func testSignInToTheSandboxBackendAndSeeBalances() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let email = environment["WALLET_E2E_EMAIL"], let password = environment["WALLET_E2E_PASSWORD"] else {
            throw XCTSkip("Set WALLET_E2E_EMAIL and WALLET_E2E_PASSWORD and run the backend to enable.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let emailField = app.textFields["auth.email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 10))
        emailField.tap()
        emailField.typeText(email)
        app.secureTextFields["auth.password"].tap()
        app.secureTextFields["auth.password"].typeText(password)
        app.buttons["auth.submit"].tap()
        XCTAssertTrue(app.staticTexts["auth.createPIN.prompt"].waitForExistence(timeout: 15))
        enterPIN("123456", in: app)
        enterPIN("123456", in: app)

        XCTAssertTrue(app.buttons["accounts.card.acc_sgd"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["accounts.card.acc_kwd"].label.localizedCaseInsensitiveContains("Kuwaiti dinars"))

        // Leave no session in the simulator's Keychain.
        app.terminate()
        app.launchArguments += ["-resetSession"]
        app.launch()
        XCTAssertTrue(app.textFields["auth.email"].waitForExistence(timeout: 10))
    }
}
