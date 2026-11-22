import SQLKit
import XCTVapor

@testable import WalletBackend

func transferRequest(quote: QuoteDTO, id: UUID = UUID()) -> TransferRequest {
    TransferRequest(
        id: id.uuidString.lowercased(),
        quoteId: quote.id,
        recipientId: "rcp_alice_usd",
        sourceAccountId: "acc_sgd"
    )
}

func transferCount(_ harness: Harness) async throws -> Int {
    let sql = try harness.app.db.sqlDatabase()
    return try await sql.select().column("id").from("transfers").all().count
}

/// A transfer request that should be rejected, with the status and code expected.
struct InvalidTransfer {
    let body: TransferRequest
    let status: HTTPResponseStatus
    let code: String

    init(
        id: String = UUID().uuidString,
        quote: String,
        recipient: String = "rcp_alice_usd",
        account: String = "acc_sgd",
        expect status: HTTPResponseStatus,
        _ code: String
    ) {
        body = TransferRequest(id: id, quoteId: quote, recipientId: recipient, sourceAccountId: account)
        self.status = status
        self.code = code
    }
}

final class TransferTests: XCTestCase {
    func testCreateRecordsTransferAwaitingConfirmation() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()
            let quote = try await harness.quote(token: tokens.accessToken)
            let body = transferRequest(quote: quote)

            let response = try await harness.send(
                .POST,
                "/v1/transfers",
                token: tokens.accessToken,
                headers: ["Idempotency-Key": body.id],
                json: body
            )

            XCTAssertEqual(response.status, .created)
            let transfer = try response.content.decode(TransferDTO.self)
            XCTAssertEqual(transfer.id, body.id)
            XCTAssertEqual(transfer.status, "awaiting_confirmation")
            XCTAssertEqual(transfer.sourceAmount, quote.sourceAmount)
            XCTAssertEqual(transfer.targetAmount, quote.targetAmount)
            XCTAssertEqual(transfer.fee, quote.fee)

            let status = try await harness.send(.GET, "/v1/transfers/\(body.id)", token: tokens.accessToken)
            XCTAssertEqual(status.status, .ok)
            XCTAssertEqual(try status.content.decode(TransferDTO.self).id, body.id)
        }
    }

    func testQuoteExpiresAtExactly30Seconds() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()
            let early = try await harness.quote(token: tokens.accessToken)
            let late = try await harness.quote(token: tokens.accessToken)
            harness.advance(29.5)
            let beforeExpiry = transferRequest(quote: early)
            let beforeExpiryResponse = try await harness.send(
                .POST,
                "/v1/transfers",
                token: tokens.accessToken,
                headers: ["Idempotency-Key": beforeExpiry.id],
                json: beforeExpiry
            )

            harness.advance(0.5)
            let atExpiry = transferRequest(quote: late)
            let expired = try await harness.send(
                .POST,
                "/v1/transfers",
                token: tokens.accessToken,
                headers: ["Idempotency-Key": atExpiry.id],
                json: atExpiry
            )

            XCTAssertEqual(beforeExpiryResponse.status, .created)
            XCTAssertEqual(expired.status, .unprocessableEntity)
            XCTAssertEqual(expired.envelope?.code, "quote_expired")
        }
    }

    func testQuoteCanPayForOneTransferOnly() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()
            let quote = try await harness.quote(token: tokens.accessToken)
            let first = transferRequest(quote: quote)
            let second = transferRequest(quote: quote)

            _ = try await harness.send(
                .POST, "/v1/transfers", token: tokens.accessToken, headers: ["Idempotency-Key": first.id], json: first)
            let reuse = try await harness.send(
                .POST, "/v1/transfers", token: tokens.accessToken, headers: ["Idempotency-Key": second.id], json: second
            )

            XCTAssertEqual(reuse.status, .conflict)
            XCTAssertEqual(reuse.envelope?.code, "quote_used")
        }
    }

    func testValidationFailures() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()
            let large = try await harness.quote(token: tokens.accessToken, minor: 2_000_000)  // more than acc_sgd holds
            let small = try await harness.quote(token: tokens.accessToken)
            let cases = [
                InvalidTransfer(id: "not-a-uuid", quote: small.id, expect: .unprocessableEntity, "invalid_request"),
                InvalidTransfer(quote: "q_missing", expect: .notFound, "not_found"),
                InvalidTransfer(
                    quote: small.id,
                    recipient: "rcp_kenji_jpy",
                    expect: .unprocessableEntity,
                    "invalid_request"
                ),
                InvalidTransfer(quote: small.id, account: "acc_usd", expect: .unprocessableEntity, "invalid_request"),
                InvalidTransfer(quote: small.id, recipient: "rcp_other_usd", expect: .notFound, "not_found"),
                InvalidTransfer(quote: small.id, account: "acc_other_sgd", expect: .notFound, "not_found"),
                InvalidTransfer(quote: large.id, expect: .unprocessableEntity, "insufficient_funds"),
            ]
            for invalid in cases {
                let response = try await harness.send(
                    .POST,
                    "/v1/transfers",
                    token: tokens.accessToken,
                    headers: ["Idempotency-Key": invalid.body.id],
                    json: invalid.body
                )
                XCTAssertEqual(response.status, invalid.status, invalid.code)
                XCTAssertEqual(response.envelope?.code, invalid.code)
            }
            let count = try await transferCount(harness)
            XCTAssertEqual(count, 0)
        }
    }

    func testAnotherUsersTransferIsNotFound() async throws {
        try await withApp { harness in
            let demo = try await harness.login()
            let other = try await harness.login(email: Sandbox.otherEmail, password: Sandbox.otherPassword)
            let quote = try await harness.quote(token: demo.accessToken)
            let body = transferRequest(quote: quote)
            _ = try await harness.send(
                .POST, "/v1/transfers", token: demo.accessToken, headers: ["Idempotency-Key": body.id], json: body)

            let response = try await harness.send(.GET, "/v1/transfers/\(body.id)", token: other.accessToken)

            XCTAssertEqual(response.status, .notFound)
        }
    }

    func testCreatingWithAnotherUsersTransferIDIsNotFound() async throws {
        try await withApp { harness in
            let demo = try await harness.login()
            let other = try await harness.login(email: Sandbox.otherEmail, password: Sandbox.otherPassword)
            let quote = try await harness.quote(token: demo.accessToken)
            let body = transferRequest(quote: quote)
            let headers: HTTPHeaders = ["Idempotency-Key": body.id]
            _ = try await harness.send(.POST, "/v1/transfers", token: demo.accessToken, headers: headers, json: body)

            let response = try await harness.send(
                .POST, "/v1/transfers", token: other.accessToken, headers: headers, json: body)

            // Same answer as for an ID nobody uses, so it doesn't reveal the demo user's transfer.
            XCTAssertEqual(response.status, .notFound)
            XCTAssertEqual(response.envelope?.code, "not_found")
        }
    }
}
