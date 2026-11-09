import XCTest

/// Phase 4 "done when": balances show with their currency for VoiceOver, history pages
/// in as you scroll, and offline shows a clear error instead of balances (ADR-017).
final class AccountsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBalancesShowAndVoiceOverReadsTheCurrency() throws {
        let app = launchApp()
        signIn(app)

        let sgd = app.buttons["accounts.card.acc_sgd"]
        XCTAssertTrue(sgd.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["accounts.card.acc_usd"].exists)
        XCTAssertTrue(app.buttons["accounts.card.acc_jpy"].exists)
        XCTAssertTrue(app.buttons["accounts.card.acc_kwd"].exists)
        // What VoiceOver speaks: the amount with the currency in words, not "SGD".
        XCTAssertTrue(
            sgd.label.localizedCaseInsensitiveContains("12,500.00 Singapore dollars"),
            "label was: \(sgd.label)"
        )
        XCTAssertTrue(
            app.buttons["accounts.card.acc_jpy"].label.localizedCaseInsensitiveContains("150,000 Japanese yen"),
            "label was: \(app.buttons["accounts.card.acc_jpy"].label)"
        )
    }

    @MainActor
    func testHistoryLoadsTheNextPageWhenScrolledToTheEnd() throws {
        let app = launchApp()
        signIn(app)
        let sgd = app.buttons["accounts.card.acc_sgd"]
        XCTAssertTrue(sgd.waitForExistence(timeout: 10))

        sgd.tap()

        // Newest first: txn_sgd_44 is on page 1, txn_sgd_24 is the first row of page 2.
        XCTAssertTrue(app.descendants(matching: .any)["account.transaction.txn_sgd_44"].waitForExistence(timeout: 10))
        let firstOfPageTwo = app.descendants(matching: .any)["account.transaction.txn_sgd_24"]
        for _ in 0..<15 where !firstOfPageTwo.exists {
            app.swipeUp()
        }
        XCTAssertTrue(firstOfPageTwo.waitForExistence(timeout: 5))
    }

    @MainActor
    func testOfflineShowsTheErrorAndNoBalances() throws {
        let app = launchApp(["-simulateOffline"])
        signIn(app)

        XCTAssertTrue(app.buttons["accounts.retry"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["You're offline"].exists)
        XCTAssertFalse(app.buttons["accounts.card.acc_sgd"].exists)
    }
}
