import XCTest

/// Phase 5 "done when": sign-in, PIN, and the app locking itself after inactivity.
final class AuthUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWrongPasswordShowsAnError() throws {
        let app = launchApp()
        let email = app.textFields["auth.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        email.tap()
        email.typeText("demo@wallet.test")
        app.secureTextFields["auth.password"].tap()
        app.secureTextFields["auth.password"].typeText("wrong")

        app.buttons["auth.submit"].tap()

        XCTAssertTrue(app.staticTexts["Email or password is incorrect."].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLocksAfterInactivityAndUnlocksWithThePIN() throws {
        let app = launchApp(["-autoLockSeconds", "3"])
        signIn(app)
        XCTAssertTrue(app.buttons["accounts.card.acc_sgd"].waitForExistence(timeout: 10))

        // No touches for longer than the limit: the unlock screen replaces the balances.
        let unlockMessage = app.staticTexts["auth.unlock.message"]
        XCTAssertTrue(unlockMessage.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["accounts.card.acc_sgd"].exists)

        enterPIN("123456", in: app)

        XCTAssertTrue(app.buttons["accounts.card.acc_sgd"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testWrongPINSaysHowManyAttemptsAreLeft() throws {
        let app = launchApp(["-autoLockSeconds", "3"])
        signIn(app)
        let unlockMessage = app.staticTexts["auth.unlock.message"]
        XCTAssertTrue(unlockMessage.waitForExistence(timeout: 10))

        enterPIN("000000", in: app)

        let predicate = NSPredicate(format: "label == %@", "4 attempts left.")
        expectation(for: predicate, evaluatedWith: unlockMessage)
        waitForExpectations(timeout: 5)
    }

    @MainActor
    func testSignOutFromTheLockScreenReturnsToSignIn() throws {
        let app = launchApp(["-autoLockSeconds", "3"])
        signIn(app)
        XCTAssertTrue(app.buttons["auth.unlock.signOut"].waitForExistence(timeout: 10))

        app.buttons["auth.unlock.signOut"].tap()

        XCTAssertTrue(app.textFields["auth.email"].waitForExistence(timeout: 5))
    }
}
