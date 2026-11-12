import SQLKit
import XCTVapor

@testable import WalletBackend

final class TransferConfirmTests: XCTestCase {
    func testConfirmDebitsOnceAndAddsTheHistoryRow() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()
            let transfer = try await created(harness, tokens.accessToken, minor: 10_000)

            let first = try await Self.confirm(harness, tokens.accessToken, transfer.id)
            let again = try await Self.confirm(harness, tokens.accessToken, transfer.id)

            XCTAssertEqual(first.status, .ok)
            XCTAssertEqual(try first.content.decode(TransferDTO.self).status, "processing")
            XCTAssertEqual(try again.content.decode(TransferDTO.self).status, "processing")
            let balance = try await balanceMinor(harness, "acc_sgd")
            XCTAssertEqual(balance, 1_250_000 - 10_000)
            let rows = try await historyRows(harness, id: "txn_\(transfer.id)")
            XCTAssertEqual(rows, 1)
        }
    }

    /// Each transfer fits the balance when created, but the second no longer fits once the
    /// first is confirmed: it fails and nothing more is debited.
    func testConfirmWithoutEnoughBalanceFailsAndDebitsNothing() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()
            let first = try await created(harness, tokens.accessToken, minor: 1_000_000)
            let second = try await created(harness, tokens.accessToken, minor: 1_000_000)
            _ = try await Self.confirm(harness, tokens.accessToken, first.id)

            let response = try await Self.confirm(harness, tokens.accessToken, second.id)

            let failed = try response.content.decode(TransferDTO.self)
            XCTAssertEqual(failed.status, "failed")
            XCTAssertEqual(failed.failureReason, "insufficient_funds")
            let balance = try await balanceMinor(harness, "acc_sgd")
            XCTAssertEqual(balance, 250_000)
        }
    }

    func testAnotherUsersTransferIsNotFound() async throws {
        try await withApp { harness in
            let demo = try await harness.login()
            let transfer = try await created(harness, demo.accessToken, minor: 10_000)
            let other = try await harness.login(email: Sandbox.otherEmail, password: Sandbox.otherPassword)

            let response = try await Self.confirm(harness, other.accessToken, transfer.id)
            let unknown = try await Self.confirm(harness, demo.accessToken, UUID().uuidString)

            XCTAssertEqual(response.status, .notFound)
            XCTAssertEqual(unknown.status, .notFound)
            let balance = try await balanceMinor(harness, "acc_sgd")
            XCTAssertEqual(balance, 1_250_000)
        }
    }

    func testProcessingSettlesAfterThreeSeconds() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()
            let transfer = try await created(harness, tokens.accessToken, minor: 10_000)
            _ = try await Self.confirm(harness, tokens.accessToken, transfer.id)

            harness.advance(2)
            let early = try await status(harness, tokens.accessToken, transfer.id)
            harness.advance(1)
            let settled = try await status(harness, tokens.accessToken, transfer.id)

            XCTAssertEqual(early.status, "processing")
            XCTAssertEqual(settled.status, "completed")
        }
    }

    /// The sandbox's declined payee: settlement fails and the debit comes back.
    func testDeclinedTransferIsRefunded() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()
            let transfer = try await created(
                harness, tokens.accessToken, minor: 10_000, to: "EUR", recipient: Sandbox.declinedRecipientID)
            _ = try await Self.confirm(harness, tokens.accessToken, transfer.id)

            harness.advance(3)
            let declined = try await status(harness, tokens.accessToken, transfer.id)
            let again = try await status(harness, tokens.accessToken, transfer.id)

            XCTAssertEqual(declined.status, "failed")
            XCTAssertEqual(declined.failureReason, "declined")
            XCTAssertEqual(again.status, "failed")
            let balance = try await balanceMinor(harness, "acc_sgd")
            XCTAssertEqual(balance, 1_250_000)
            let refunds = try await historyRows(harness, id: "txn_\(transfer.id)_refund")
            XCTAssertEqual(refunds, 1)
        }
    }

    /// An old rate isn't a free option: a confirm long after the quote expired fails and
    /// debits nothing.
    func testConfirmLongAfterTheQuoteExpiredFails() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()
            let transfer = try await created(harness, tokens.accessToken, minor: 10_000)

            harness.advance(30 + 121)
            let response = try await Self.confirm(harness, tokens.accessToken, transfer.id)

            let failed = try response.content.decode(TransferDTO.self)
            XCTAssertEqual(failed.status, "failed")
            XCTAssertEqual(failed.failureReason, "quote_expired")
            let balance = try await balanceMinor(harness, "acc_sgd")
            XCTAssertEqual(balance, 1_250_000)
        }
    }

    /// Within the grace period a retry after the quote expired still goes through.
    func testConfirmShortlyAfterTheQuoteExpiredStillWorks() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()
            let transfer = try await created(harness, tokens.accessToken, minor: 10_000)

            harness.advance(30 + 60)
            let response = try await Self.confirm(harness, tokens.accessToken, transfer.id)

            XCTAssertEqual(try response.content.decode(TransferDTO.self).status, "processing")
        }
    }

    /// The same confirm twice at once: one debit, one history row.
    func testConcurrentConfirmsOfOneTransferDebitOnce() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()
            let transfer = try await created(harness, tokens.accessToken, minor: 10_000)

            async let first = Self.confirm(harness, tokens.accessToken, transfer.id)
            async let second = Self.confirm(harness, tokens.accessToken, transfer.id)
            _ = try await (first, second)

            let balance = try await balanceMinor(harness, "acc_sgd")
            XCTAssertEqual(balance, 1_250_000 - 10_000)
            let rows = try await historyRows(harness, id: "txn_\(transfer.id)")
            XCTAssertEqual(rows, 1)
        }
    }

    /// Two transfers that each fit but not together, confirmed at once. The loser is either
    /// refused or rolled back with a 5xx (SQLite lets one writer through), which the app
    /// retries. Either way one goes through, the other fails, and nothing is overdrawn.
    func testConcurrentConfirmsNeverOverdraw() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()
            let first = try await created(harness, tokens.accessToken, minor: 1_000_000)
            let second = try await created(harness, tokens.accessToken, minor: 1_000_000)

            async let one = Self.confirm(harness, tokens.accessToken, first.id)
            async let two = Self.confirm(harness, tokens.accessToken, second.id)
            _ = try await (one, two)
            var statuses: [String] = []
            for id in [first.id, second.id] {
                // The app's retry: confirming again is safe.
                let retried = try await Self.confirm(harness, tokens.accessToken, id)
                statuses.append(try retried.content.decode(TransferDTO.self).status)
            }

            XCTAssertEqual(statuses.sorted(), ["failed", "processing"])
            let balance = try await balanceMinor(harness, "acc_sgd")
            XCTAssertEqual(balance, 250_000)
        }
    }

    // MARK: - Helpers

    private func created(
        _ harness: Harness,
        _ token: String,
        minor: Int64,
        to target: String = "USD",
        recipient: String = "rcp_alice_usd"
    ) async throws -> TransferDTO {
        let quote = try await harness.quote(token: token, minor: minor, to: target)
        let id = UUID().uuidString.lowercased()
        let body = TransferRequest(id: id, quoteId: quote.id, recipientId: recipient, sourceAccountId: "acc_sgd")
        let response = try await harness.send(
            .POST, "/v1/transfers", token: token, headers: ["Idempotency-Key": id], json: body)
        XCTAssertEqual(response.status, .created)
        return try response.content.decode(TransferDTO.self)
    }

    private static func confirm(_ harness: Harness, _ token: String, _ id: String) async throws -> XCTHTTPResponse {
        try await harness.send(.POST, "/v1/transfers/\(id)/confirm", token: token)
    }

    private func status(_ harness: Harness, _ token: String, _ id: String) async throws -> TransferDTO {
        let response = try await harness.send(.GET, "/v1/transfers/\(id)", token: token)
        XCTAssertEqual(response.status, .ok)
        return try response.content.decode(TransferDTO.self)
    }

    private func balanceMinor(_ harness: Harness, _ accountID: String) async throws -> Int64? {
        let sql = try harness.app.db.sqlDatabase()
        return try await sql.select().column("*").from("accounts")
            .where("id", .equal, accountID)
            .first(decoding: AccountRow.self)?.balanceMinor
    }

    private func historyRows(_ harness: Harness, id: String) async throws -> Int {
        let sql = try harness.app.db.sqlDatabase()
        return try await sql.select().column("id").from("transactions").where("id", .equal, id).all().count
    }
}
