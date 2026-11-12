import XCTest

/// Phase 6 "done when": one transfer per double tap, a visible re-quote, and a transfer that
/// survives the app being killed. Runs on the in-app mock bank (`-mockServer`).
final class TransferUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSendMoneyEndsSentAndShowsInTheHistory() throws {
        let app = launchApp()
        signIn(app)
        openReview(app)

        app.buttons["transfer.review.send"].tap()

        let title = app.staticTexts["transfer.status.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForLabel(title, "Sent", timeout: 10))
        app.buttons["transfer.status.done"].tap()
        XCTAssertEqual(transferIDs(to: "Alice Tan", in: app).count, 1)
    }

    @MainActor
    func testDoubleTapOnSendCreatesOneTransfer() throws {
        let app = launchApp()
        signIn(app)
        openReview(app)

        app.buttons["transfer.review.send"].doubleTap()

        let title = app.staticTexts["transfer.status.title"]
        XCTAssertTrue(waitForLabel(title, "Sent", timeout: 10))
        app.buttons["transfer.status.done"].tap()
        XCTAssertEqual(transferIDs(to: "Alice Tan", in: app).count, 1)
    }

    /// Quotes hold 3 s here. At 0 the new rate appears with a notice, and Send waits for OK.
    @MainActor
    func testExpiredQuoteIsReplacedVisibly() throws {
        let app = launchApp(["-quoteSeconds", "3"])
        signIn(app)
        openReview(app)

        XCTAssertTrue(app.staticTexts["transfer.review.rateUpdated"].waitForExistence(timeout: 10))
        let send = app.buttons["transfer.review.send"]
        XCTAssertFalse(send.isEnabled)

        app.buttons["transfer.review.rateUpdated.ok"].tap()

        XCTAssertTrue(send.isEnabled)
    }

    /// Killed while the create is on the network; on relaunch the outbox sends it before the
    /// user has even unlocked. The session survives the kill (`-keepMockSession`); the mock
    /// bank doesn't, so the history row proves the relaunched app sent it.
    @MainActor
    func testTransferKilledMidSendFinishesAfterRelaunch() throws {
        let app = launchApp(["-keepMockSession", "-resetSession", "-transferDelay", "5"])
        signIn(app)
        openReview(app)
        app.buttons["transfer.review.send"].tap()
        XCTAssertTrue(waitForLabel(app.staticTexts["transfer.status.title"], "Sending", timeout: 10))

        app.terminate()
        let relaunched = launchApp(["-keepMockSession"])
        XCTAssertTrue(relaunched.staticTexts["auth.unlock.message"].waitForExistence(timeout: 10))
        enterPIN("123456", in: relaunched)

        XCTAssertTrue(relaunched.buttons["accounts.card.acc_sgd"].waitForExistence(timeout: 10))
        relaunched.buttons["accounts.card.acc_sgd"].tap()
        let row = historyRows(to: "Alice Tan", in: relaunched).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))

        // Leave no session behind for the next test.
        relaunched.terminate()
        launchApp(["-keepMockSession", "-resetSession"]).terminate()
    }

    // MARK: - Helpers

    /// Accounts → SGD → Send money → Alice Tan → 100 → Continue, ending on the review.
    @MainActor
    private func openReview(_ app: XCUIApplication) {
        let card = app.buttons["accounts.card.acc_sgd"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        let sendMoney = app.buttons["account.sendMoney"]
        XCTAssertTrue(sendMoney.waitForExistence(timeout: 10))
        sendMoney.tap()
        let alice = app.buttons["transfer.recipient.rcp_alice_usd"]
        XCTAssertTrue(alice.waitForExistence(timeout: 10))
        alice.tap()
        let amount = app.textFields["You send"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        amount.tap()
        amount.typeText("100")
        app.buttons["transfer.continue"].tap()
        XCTAssertTrue(app.buttons["transfer.review.send"].waitForExistence(timeout: 10))
    }

    /// The distinct history rows for transfers to `name`. Each row is matched by more than one
    /// element (the cell and the row in it), so rows are counted by their transaction ID.
    @MainActor
    private func transferIDs(to name: String, in app: XCUIApplication) -> Set<String> {
        let rows = historyRows(to: name, in: app)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        return Set(
            rows.allElementsBoundByIndex.map(\.identifier).filter {
                $0.hasPrefix("account.transaction.txn_")
            })
    }

    @MainActor
    private func historyRows(to name: String, in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "To \(name)"))
    }

    @MainActor
    private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval) -> Bool {
        let matches = NSPredicate(format: "label == %@", label)
        return XCTWaiter().wait(for: [expectation(for: matches, evaluatedWith: element)], timeout: timeout)
            == .completed
    }
}
