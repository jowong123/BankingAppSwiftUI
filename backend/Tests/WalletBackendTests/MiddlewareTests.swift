import SQLKit
import XCTVapor

@testable import WalletBackend

final class RequestIDAndEnvelopeTests: XCTestCase {
    func testClientRequestIDIsEchoedOnSuccessAndInErrors() async throws {
        try await withApp { harness in
            let response = try await harness.send(.GET, "/v1/accounts", headers: ["X-Request-ID": "req-abc_123"])

            XCTAssertEqual(response.status, .unauthorized)
            XCTAssertEqual(response.headers.first(name: "X-Request-ID"), "req-abc_123")
            XCTAssertEqual(
                response.envelope,
                ErrorEnvelope(code: "unauthorized", message: "Sign in again.", requestId: "req-abc_123")
            )
        }
    }

    func testMissingOrUnsafeRequestIDIsReplaced() async throws {
        try await withApp { harness in
            let missing = try await harness.send(.GET, "/v1/accounts")
            let unsafe = try await harness.send(
                .GET, "/v1/accounts", headers: ["X-Request-ID": "abc\ninjected log line"])

            for response in [missing, unsafe] {
                let id = try XCTUnwrap(response.headers.first(name: "X-Request-ID"))
                XCTAssertNotNil(UUID(uuidString: id))
                XCTAssertEqual(response.envelope?.requestId, id)
            }
        }
    }

    func testResponsesAreNeverCached() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()

            let success = try await harness.send(.GET, "/v1/accounts", token: tokens.accessToken)
            let failure = try await harness.send(.GET, "/v1/accounts")

            XCTAssertEqual(success.headers.first(name: .cacheControl), "no-store")
            XCTAssertEqual(failure.headers.first(name: .cacheControl), "no-store")
        }
    }

    func testUnknownRouteUsesTheEnvelope() async throws {
        try await withApp { harness in
            let response = try await harness.send(.GET, "/v1/nope")

            XCTAssertEqual(response.status, .notFound)
            XCTAssertEqual(response.envelope?.code, "not_found")
        }
    }

    func testMalformedJSONIsABadRequestWithoutDetails() async throws {
        try await withApp { harness in
            let response = try await harness.app.testable().performTest(
                request: XCTHTTPRequest(
                    method: .POST,
                    url: URI(path: "/v1/auth/login"),
                    headers: ["Content-Type": "application/json"],
                    body: ByteBuffer(string: #"{"email": "#)
                )
            )

            XCTAssertEqual(response.status, .badRequest)
            XCTAssertEqual(response.envelope?.code, "bad_request")
        }
    }
}

final class SimulationTests: XCTestCase {
    func testServerFailureHappensBeforeAnyWork() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()

            let response = try await harness.send(
                .POST,
                "/v1/quotes",
                token: tokens.accessToken,
                headers: ["X-Sim-Fail": "server"],
                json: QuoteRequest(sourceAmount: MoneyDTO(amountMinor: 10_000, currency: "SGD"), targetCurrency: "USD")
            )

            XCTAssertEqual(response.status, .internalServerError)
            XCTAssertEqual(response.envelope?.code, "sim_server_error")
            XCTAssertNotNil(response.envelope?.requestId)
            let quotes = try await harness.app.db.sqlDatabase().select().column("id").from("quotes").all()
            XCTAssertTrue(quotes.isEmpty)
        }
    }

    func testDeclined() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()

            let response = try await harness.send(
                .GET,
                "/v1/accounts",
                token: tokens.accessToken,
                headers: ["X-Sim-Fail": "declined"]
            )

            XCTAssertEqual(response.status, .unprocessableEntity)
            XCTAssertEqual(response.envelope?.code, "declined")
        }
    }

    /// The case idempotency exists for: the server did the work, the client never heard back.
    func testNetworkFailureDropsTheResponseAfterTheWorkIsDoneAndARetryReplaysIt() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()
            let quote = try await harness.quote(token: tokens.accessToken)
            let body = TransferRequest(
                id: UUID().uuidString.lowercased(),
                quoteId: quote.id,
                recipientId: "rcp_alice_usd",
                sourceAccountId: "acc_sgd"
            )

            do {
                _ = try await harness.send(
                    .POST,
                    "/v1/transfers",
                    token: tokens.accessToken,
                    headers: ["Idempotency-Key": body.id, "X-Sim-Fail": "network"],
                    json: body
                )
                XCTFail("Expected the response stream to fail")
            } catch {
                XCTAssertTrue(error is SimulatedNetworkDrop, String(reflecting: error))
            }

            let retry = try await harness.send(
                .POST,
                "/v1/transfers",
                token: tokens.accessToken,
                headers: ["Idempotency-Key": body.id],
                json: body
            )
            XCTAssertEqual(retry.status, .created)
            XCTAssertEqual(retry.headers.first(name: "Idempotent-Replayed"), "true")
            XCTAssertEqual(try retry.content.decode(TransferDTO.self).id, body.id)
        }
    }

    func testDelayWaitsBeforeHandling() async throws {
        try await withApp { harness in
            let start = ContinuousClock.now

            let response = try await harness.send(.GET, "/v1/accounts", headers: ["X-Sim-Delay": "150"])

            XCTAssertEqual(response.status, .unauthorized)
            XCTAssertGreaterThanOrEqual(ContinuousClock.now - start, .milliseconds(150))
        }
    }

    func testInvalidSimulationHeadersAreRejected() async throws {
        try await withApp { harness in
            for headers: HTTPHeaders in [
                ["X-Sim-Fail": "meteor"], ["X-Sim-Delay": "-1"], ["X-Sim-Delay": "30001"], ["X-Sim-Delay": "soon"],
            ] {
                let response = try await harness.send(.GET, "/v1/accounts", headers: headers)
                XCTAssertEqual(response.status, .badRequest, "\(headers)")
                XCTAssertEqual(response.envelope?.code, "bad_request")
            }
        }
    }

    func testSimulationHeadersAreIgnoredWhenDisabled() async throws {
        try await withApp(simulation: false) { harness in
            let tokens = try await harness.login()

            let response = try await harness.send(
                .GET,
                "/v1/accounts",
                token: tokens.accessToken,
                headers: ["X-Sim-Fail": "server"]
            )

            XCTAssertEqual(response.status, .ok)
        }
    }

    func testSimulationIsOffUnlessExplicitlyTurnedOn() {
        XCTAssertTrue(BackendEnvironment.simulationEnabled(setting: "on"))
        for setting in [nil, "", "off", "true", "ON", "1"] {
            XCTAssertFalse(BackendEnvironment.simulationEnabled(setting: setting), "\(setting ?? "nil")")
        }
    }
}
