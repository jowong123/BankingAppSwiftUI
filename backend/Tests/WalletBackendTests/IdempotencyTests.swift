import SQLKit
import XCTVapor

@testable import WalletBackend

/// `Idempotency-Key` handling on `POST /v1/transfers` (SPEC section 7).
final class IdempotencyTests: XCTestCase {
    func testIdempotencyKeyIsRequired() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()
            let quote = try await harness.quote(token: tokens.accessToken)

            let response = try await harness.send(
                .POST,
                "/v1/transfers",
                token: tokens.accessToken,
                json: transferRequest(quote: quote)
            )

            XCTAssertEqual(response.status, .badRequest)
            XCTAssertEqual(response.envelope?.code, "idempotency_key_required")
            let count = try await transferCount(harness)
            XCTAssertEqual(count, 0)
        }
    }

    func testSameKeyAndBodyReplaysTheOriginalResponseAndCreatesOneTransfer() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()
            let quote = try await harness.quote(token: tokens.accessToken)
            let body = transferRequest(quote: quote)
            let headers: HTTPHeaders = ["Idempotency-Key": body.id]

            let first = try await harness.send(
                .POST, "/v1/transfers", token: tokens.accessToken, headers: headers, json: body)
            let second = try await harness.send(
                .POST, "/v1/transfers", token: tokens.accessToken, headers: headers, json: body)

            XCTAssertEqual(first.status, .created)
            XCTAssertEqual(second.status, .created)
            XCTAssertEqual(first.body.string, second.body.string)
            XCTAssertNil(first.headers.first(name: "Idempotent-Replayed"))
            XCTAssertEqual(second.headers.first(name: "Idempotent-Replayed"), "true")
            let count = try await transferCount(harness)
            XCTAssertEqual(count, 1)
        }
    }

    func testReplayStillWorksAfterTheQuoteExpires() async throws {
        // A retry after a long timeout must return the transfer, not "quote expired".
        try await withApp { harness in
            let tokens = try await harness.login()
            let quote = try await harness.quote(token: tokens.accessToken)
            let body = transferRequest(quote: quote)
            let headers: HTTPHeaders = ["Idempotency-Key": body.id]

            _ = try await harness.send(.POST, "/v1/transfers", token: tokens.accessToken, headers: headers, json: body)
            harness.advance(60)
            let retry = try await harness.send(
                .POST, "/v1/transfers", token: tokens.accessToken, headers: headers, json: body)

            XCTAssertEqual(retry.status, .created)
            XCTAssertEqual(retry.headers.first(name: "Idempotent-Replayed"), "true")
        }
    }

    func testSameKeyWithDifferentBodyIsRejected() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()
            let quote = try await harness.quote(token: tokens.accessToken)
            let body = transferRequest(quote: quote)
            let headers: HTTPHeaders = ["Idempotency-Key": body.id]
            _ = try await harness.send(.POST, "/v1/transfers", token: tokens.accessToken, headers: headers, json: body)

            let changed = TransferRequest(
                id: body.id,
                quoteId: body.quoteId,
                recipientId: "rcp_kenji_jpy",
                sourceAccountId: body.sourceAccountId
            )
            let response = try await harness.send(
                .POST, "/v1/transfers", token: tokens.accessToken, headers: headers, json: changed)

            XCTAssertEqual(response.status, .unprocessableEntity)
            XCTAssertEqual(response.envelope?.code, "idempotency_mismatch")
        }
    }

    func testKeysAreScopedPerUser() async throws {
        try await withApp { harness in
            let demo = try await harness.login()
            let other = try await harness.login(email: Sandbox.otherEmail, password: Sandbox.otherPassword)
            let headers: HTTPHeaders = ["Idempotency-Key": "shared-key"]
            let body = QuoteRequest(sourceAmount: MoneyDTO(amountMinor: 10_000, currency: "SGD"), targetCurrency: "USD")

            let first = try await harness.send(
                .POST, "/v1/quotes", token: demo.accessToken, headers: headers, json: body)
            let second = try await harness.send(
                .POST, "/v1/quotes", token: other.accessToken, headers: headers, json: body)

            XCTAssertEqual(first.status, .created)
            XCTAssertEqual(second.status, .created)
            XCTAssertNil(second.headers.first(name: "Idempotent-Replayed"))
            XCTAssertNotEqual(try first.content.decode(QuoteDTO.self).id, try second.content.decode(QuoteDTO.self).id)
        }
    }

    func testQuotesHonourAnOptionalKey() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()
            let headers: HTTPHeaders = ["Idempotency-Key": "quote-key"]
            let body = QuoteRequest(sourceAmount: MoneyDTO(amountMinor: 10_000, currency: "SGD"), targetCurrency: "USD")

            let first = try await harness.send(
                .POST, "/v1/quotes", token: tokens.accessToken, headers: headers, json: body)
            let second = try await harness.send(
                .POST, "/v1/quotes", token: tokens.accessToken, headers: headers, json: body)

            XCTAssertEqual(first.body.string, second.body.string)
            XCTAssertEqual(second.headers.first(name: "Idempotent-Replayed"), "true")
        }
    }

    func testKeyMustBeTheTransferID() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()
            let quote = try await harness.quote(token: tokens.accessToken)
            let body = transferRequest(quote: quote)

            let response = try await harness.send(
                .POST,
                "/v1/transfers",
                token: tokens.accessToken,
                headers: ["Idempotency-Key": UUID().uuidString],
                json: body
            )

            XCTAssertEqual(response.status, .unprocessableEntity)
            XCTAssertEqual(response.envelope?.code, "idempotency_mismatch")
            let count = try await transferCount(harness)
            XCTAssertEqual(count, 0)
        }
    }

    func testCrashedClaimBlocksRetriesOnlyUntilItsLeaseRunsOut() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()
            let quote = try await harness.quote(token: tokens.accessToken)
            let body = transferRequest(quote: quote)
            // A request with this exact body claimed the key 50 s ago and then died.
            let startMillis = Int64(Harness.start.timeIntervalSince1970 * 1000)
            try await harness.app.db.sqlDatabase().insert(into: "idempotency").model(
                IdempotencyRow(
                    scopedKey: "usr_demo:\(body.id)",
                    method: "POST",
                    path: "/v1/transfers",
                    bodyHash: SHA256.hash(data: try JSONEncoder().encode(body)).hex,
                    lockOwner: "crashed",
                    completed: 0,
                    status: 0,
                    responseBody: Data(),
                    createdAt: startMillis - 50_000
                )
            ).run()
            let headers: HTTPHeaders = ["Idempotency-Key": body.id]

            let blocked = try await harness.send(
                .POST, "/v1/transfers", token: tokens.accessToken, headers: headers, json: body)
            harness.advance(11)  // the claim is now 61 s old
            let takenOver = try await harness.send(
                .POST, "/v1/transfers", token: tokens.accessToken, headers: headers, json: body)

            XCTAssertEqual(blocked.status, .conflict)
            XCTAssertEqual(blocked.envelope?.code, "idempotency_in_progress")
            XCTAssertEqual(takenOver.status, .created)
        }
    }

    func testFailedRequestReleasesTheKeySoARetryRunsAgain() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()
            let quote = try await harness.quote(token: tokens.accessToken)
            let body = transferRequest(quote: quote)
            let headers: HTTPHeaders = ["Idempotency-Key": body.id]

            let failed = try await harness.send(
                .POST,
                "/v1/transfers",
                token: tokens.accessToken,
                headers: ["Idempotency-Key": body.id, "X-Sim-Fail": "server"],
                json: body
            )
            let retry = try await harness.send(
                .POST, "/v1/transfers", token: tokens.accessToken, headers: headers, json: body)

            XCTAssertEqual(failed.status, .internalServerError)
            XCTAssertEqual(retry.status, .created)
            XCTAssertNil(retry.headers.first(name: "Idempotent-Replayed"))
        }
    }

    func testRetryAfterTheRecordExpiresStillReturnsTheTransfer() async throws {
        // The record is gone after 24 h, but the transfer ID itself is idempotent: the
        // retry gets the transfer, not "quote expired" for a transfer that exists.
        try await withApp { harness in
            let tokens = try await harness.login()
            let quote = try await harness.quote(token: tokens.accessToken)
            let body = transferRequest(quote: quote)
            let headers: HTTPHeaders = ["Idempotency-Key": body.id]
            _ = try await harness.send(.POST, "/v1/transfers", token: tokens.accessToken, headers: headers, json: body)

            harness.advance(24 * 60 * 60)
            let fresh = try await harness.login()
            let late = try await harness.send(
                .POST, "/v1/transfers", token: fresh.accessToken, headers: headers, json: body)

            XCTAssertNil(late.headers.first(name: "Idempotent-Replayed"))
            XCTAssertEqual(late.status, .ok)
            XCTAssertEqual(try late.content.decode(TransferDTO.self).id, body.id)
            let count = try await transferCount(harness)
            XCTAssertEqual(count, 1)
        }
    }

    func testSameTransferIDWithDifferentDetailsIsAConflict() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()
            let quote = try await harness.quote(token: tokens.accessToken)
            let body = transferRequest(quote: quote)
            let headers: HTTPHeaders = ["Idempotency-Key": body.id]
            _ = try await harness.send(.POST, "/v1/transfers", token: tokens.accessToken, headers: headers, json: body)
            harness.advance(24 * 60 * 60)
            let fresh = try await harness.login()

            let changed = TransferRequest(
                id: body.id,
                quoteId: body.quoteId,
                recipientId: "rcp_kenji_jpy",
                sourceAccountId: body.sourceAccountId
            )
            let response = try await harness.send(
                .POST, "/v1/transfers", token: fresh.accessToken, headers: headers, json: changed)

            XCTAssertEqual(response.status, .conflict)
            XCTAssertEqual(response.envelope?.code, "transfer_exists")
        }
    }
}
