import Domain
import Foundation
import NetworkingKit
import Testing

@testable import Networking

let transferJSON = """
    {"id":"6f1c2e1a-0000-4000-8000-000000000001","quoteId":"q_1","recipientId":"rcp_1",
     "sourceAccountId":"acc_sgd","sourceAmount":{"amountMinor":10000,"currency":"SGD"},
     "targetAmount":{"amountMinor":7301,"currency":"USD"},"fee":{"amountMinor":150,"currency":"SGD"},
     "status":"awaiting_confirmation","failureReason":null,
     "createdAt":"2026-10-26T10:00:00Z","updatedAt":"2026-10-26T10:00:00Z"}
    """

@Suite struct WalletEndpointTests {
    @Test func transactionsPathAndQuery() throws {
        let request = try WalletEndpoints.transactions(accountID: "acc_sgd", cursor: "c_2", limit: 20).request

        #expect(request.method == .get)
        #expect(request.path == "/v1/accounts/acc_sgd/transactions")
        #expect(
            request.queryItems == [
                URLQueryItem(name: "limit", value: "20"), URLQueryItem(name: "cursor", value: "c_2"),
            ])
    }

    @Test func authCallsDoNotRequireASession() throws {
        #expect(try WalletEndpoints.login(email: "a@b.test", password: "pw").request.requiresAuthentication == false)
        #expect(try WalletEndpoints.refresh(refreshToken: "r").request.requiresAuthentication == false)
        #expect(WalletEndpoints.accounts().request.requiresAuthentication)
    }

    @Test(arguments: ["../admin", "a/b", "", "acc 1", "acc%2F1", "acc?x=1", String(repeating: "a", count: 129)])
    func idsThatCouldChangeThePathAreRejected(id: String) {
        #expect(throws: APIError.invalidRequest) { try WalletEndpoints.pathID(id) }
    }

    @Test(arguments: ["acc_sgd", "6f1c2e1a-0000-4000-8000-000000000001", "Q1"])
    func normalIDsAreAccepted(id: String) throws {
        #expect(try WalletEndpoints.pathID(id) == id)
    }
}

@Suite struct WalletAPITests {
    @Test func createTransferUsesTheTransferIDAsIdempotencyKeyOnEveryAttempt() async throws {
        let transport = StubTransport([status(503), status(201, transferJSON)])
        let api = try makeAPI(transport)
        let id = try #require(UUID(uuidString: "6F1C2E1A-0000-4000-8000-000000000001"))

        let transfer = try await api.createTransfer(
            id: id,
            quoteID: "q_1",
            recipientID: "rcp_1",
            sourceAccountID: "acc_sgd"
        )

        #expect(transfer.status == .awaitingConfirmation)
        let requests = await transport.requests
        #expect(requests.count == 2)
        for request in requests {
            #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == "6f1c2e1a-0000-4000-8000-000000000001")
            #expect(try body(of: request)["id"] as? String == "6f1c2e1a-0000-4000-8000-000000000001")
        }
    }

    @Test func createQuoteSendsMinorUnitsAndReturnsDomainQuote() async throws {
        let quoteJSON = """
            {"id":"q_1","sourceAmount":{"amountMinor":10000,"currency":"SGD"},
             "targetAmount":{"amountMinor":7301,"currency":"USD"},"fee":{"amountMinor":150,"currency":"SGD"},
             "rate":"0.7411","expiresAt":"2026-10-26T10:00:30Z"}
            """
        let transport = StubTransport([status(201, quoteJSON)])
        let api = try makeAPI(transport)

        let quote = try await api.createQuote(
            sourceAmount: Money(amountMinor: 10_000, currency: .sgd), targetCurrency: .usd)

        #expect(quote.targetAmount == Money(amountMinor: 7_301, currency: .usd))
        let sent = try body(of: try #require(await transport.requests.first))
        let source = try #require(sent["sourceAmount"] as? [String: Any])
        #expect(source["amountMinor"] as? Int == 10_000)
        #expect(source["currency"] as? String == "SGD")
        #expect(sent["targetCurrency"] as? String == "USD")
    }

    @Test func loginSendsNoBearerToken() async throws {
        let transport = StubTransport([status(200, #"{"accessToken":"a","refreshToken":"r","expiresIn":900}"#)])
        let api = try makeAPI(transport)

        _ = try await api.login(email: "demo@wallet.test", password: "pw")

        let request = try #require(await transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.httpMethod == "POST")
    }

    @Test func accountsSendBearerAndDecode() async throws {
        let body = """
            {"accounts":[{"id":"acc_jpy","currency":"JPY",
              "balance":{"amountMinor":125000,"currency":"JPY"},"updatedAt":"2026-10-26T10:00:00Z"}]}
            """
        let transport = StubTransport([status(200, body)])
        let api = try makeAPI(transport)

        let accounts = try await api.accounts()

        #expect(try accounts.first?.balance.money() == Money(amountMinor: 125_000, currency: .jpy))
        #expect(await transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer access_1")
    }

    @Test func serverErrorEnvelopeBecomesTypedError() async throws {
        let envelope = #"{"code":"quote_expired","message":"Quote has expired","requestId":"req_9"}"#
        let api = try makeAPI(StubTransport([status(422, envelope)]))

        await #expect(
            throws: APIError.server(
                status: 422, code: "quote_expired", message: "Quote has expired", requestID: "req_9")
        ) {
            try await api.transfer(id: "trf_1")
        }
    }

    @Test func errorWithoutEnvelopeKeepsTheStatus() async throws {
        let api = try makeAPI(StubTransport([status(404, "Not Found")]))

        await #expect(throws: APIError.http(status: 404)) { try await api.recipients() }
    }

    @Test func unauthorizedAfterFailedRefresh() async throws {
        let api = try makeAPI(StubTransport([status(401)]), tokens: FakeTokens(token: "old", refreshed: nil))

        await #expect(throws: APIError.unauthorized) { try await api.accounts() }
    }

    /// Only the session store saying "no session", or the server refusing the token, may
    /// lock the session. Rate limiting and an unavailable Keychain must not sign anyone out.
    @Test(arguments: [
        (SessionRefreshError.noSession as any Error, true),
        (SessionRefreshError.rejected, true),
        (APIError.server(status: 401, code: "invalid_refresh_token", message: "", requestID: nil), true),
        (APIError.server(status: 429, code: "rate_limited", message: "", requestID: nil), false),
        (APIError.transport(.notConnectedToInternet), false),
        (KeychainUnavailable(), false),
    ])
    func refreshFailureLocksTheSessionOnlyWhenDefinite(refreshError: any Error, locks: Bool) async throws {
        let tokens = FakeTokens(token: "old", refreshed: nil, refreshError: refreshError)
        let api = try makeAPI(StubTransport([status(401)]), tokens: tokens)

        do {
            _ = try await api.accounts()
            Issue.record("expected the call to fail")
        } catch {
            #expect((error == .unauthorized) == locks)
        }
    }

    @Test func timeoutOnTransferIsReportedAsOutcomeUnknown() async throws {
        let api = try makeAPI(StubTransport([.failure(.transport(.timedOut))]))

        do {
            _ = try await api.createTransfer(
                id: UUID(), quoteID: "q_1", recipientID: "rcp_1", sourceAccountID: "acc_sgd")
            Issue.record("expected a transport error")
        } catch {
            #expect(error == .transport(.timedOut))
            #expect(error.isOutcomeUnknown)
        }
    }

    /// Only an explicit rejection is a definite failure. Everything else, including
    /// cancellation, an undecodable 2xx and a 401 after a timed-out first attempt, means
    /// the transfer may exist, so the app must check its status.
    @Test(arguments: [
        (APIError.transport(.timedOut), true),
        (.http(status: 502), true),
        (.server(status: 500, code: "internal", message: "", requestID: nil), true),
        (.cancelled, true),
        (.invalidResponse("status"), true),
        (.unauthorized, true),
        (.http(status: 409), true),
        (.server(status: 409, code: "idempotency_in_progress", message: "", requestID: nil), true),
        (.server(status: 409, code: "transfer_exists", message: "", requestID: nil), true),
        (.server(status: 422, code: "some_future_code", message: "", requestID: nil), true),
        (.server(status: 422, code: "declined", message: "", requestID: nil), false),
        (.server(status: 422, code: "quote_expired", message: "", requestID: nil), false),
        (.server(status: 422, code: "insufficient_funds", message: "", requestID: nil), false),
        (.server(status: 409, code: "quote_used", message: "", requestID: nil), false),
        (.server(status: 422, code: "idempotency_mismatch", message: "", requestID: nil), false),
        (.server(status: 404, code: "not_found", message: "", requestID: nil), false),
        (.invalidRequest, false),
    ])
    func outcomeIsUnknownUnlessExplicitlyRejected(error: APIError, unknown: Bool) {
        #expect(error.isOutcomeUnknown == unknown)
        #expect(error.isDefiniteRejection == !unknown)
    }

    @Test func refreshIsNeverRetried() async throws {
        let transport = StubTransport([
            .failure(.transport(.timedOut)), status(200, #"{"accessToken":"a","refreshToken":"r","expiresIn":900}"#),
        ])
        let api = try makeAPI(transport)

        await #expect(throws: APIError.transport(.timedOut)) {
            try await api.refresh(refreshToken: "r")
        }
        #expect(await transport.requests.count == 1)
    }

    @Test func quoteForADifferentAmountIsRejected() async throws {
        let quoteJSON = """
            {"id":"q_1","sourceAmount":{"amountMinor":99999,"currency":"SGD"},
             "targetAmount":{"amountMinor":7301,"currency":"USD"},"fee":{"amountMinor":150,"currency":"SGD"},
             "rate":"0.7411","expiresAt":"2026-10-26T10:00:30Z"}
            """
        let api = try makeAPI(StubTransport([status(201, quoteJSON)]))

        await #expect(throws: APIError.invalidResponse("quote does not match request")) {
            try await api.createQuote(sourceAmount: Money(amountMinor: 10_000, currency: .sgd), targetCurrency: .usd)
        }
    }

    @Test func transactionsDecodeAMissingCursorAsTheLastPage() async throws {
        let body = """
            {"items":[{"id":"txn_1","accountId":"acc_sgd","amount":{"amountMinor":-450,"currency":"SGD"},
              "description":"Kopi Corner","createdAt":"2026-10-26T10:00:00Z"}]}
            """
        let api = try makeAPI(StubTransport([status(200, body)]))

        let page = try await api.transactions(accountID: "acc_sgd")

        #expect(page.nextCursor == nil)
        #expect(try page.items.first?.amount.money() == Money(amountMinor: -450, currency: .sgd))
    }

    @Test func sessionNeverCachesOrStoresCookies() {
        let configuration = WalletAPI.sessionConfiguration()

        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.urlCredentialStorage == nil)
    }

    /// Only a definite rejection of the refresh may lock the session; offline must not.
    @Test(arguments: [
        (APIError.transport(.notConnectedToInternet), HTTPError.transport(.notConnectedToInternet)),
        (
            .server(status: 401, code: "invalid_refresh_token", message: "", requestID: nil),
            .status(code: 401, body: Data())
        ),
        (.http(status: 503), .status(code: 503, body: Data())),
        (.unauthorized, .unauthorized),
    ])
    func refreshFailuresKeepTheirMeaningForTheAuthInterceptor(error: APIError, expected: HTTPError) {
        #expect(WalletAPI.refreshFailure(error) as? HTTPError == expected)
    }
}

/// Stands in for a Keychain error such as `errSecInteractionNotAllowed` while the device is locked.
private struct KeychainUnavailable: Error {}
