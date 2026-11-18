import Domain
import Foundation
import NetworkingKit
import Testing

@testable import Networking

@Suite struct RemoteTransferAPITests {
    let id = UUID(uuidString: "6F1C2E1A-0000-4000-8000-000000000001") ?? UUID()
    let confirmation = SignedConfirmation(
        payload: Data(#"{"nonce":"n1"}"#.utf8), signature: Data([0x30, 0x44]), assertion: Data([0xA2, 0x01]))

    func draft() throws -> TransferDraft {
        let rate = try FXRate(source: .sgd, target: .usd, rate: 0.7341)
        let quote = try FXQuote(
            id: "q_1",
            sourceAmount: Money(amountMinor: 10_000, currency: .sgd),
            targetAmount: Money(amountMinor: 7_301, currency: .usd),
            rate: rate,
            fee: Money(amountMinor: 150, currency: .sgd),
            expiresAt: .now
        )
        let recipient = Recipient(id: "rcp_1", name: "Alice Tan", currency: .usd, accountLast4: "4821")
        return TransferDraft(
            id: id, quote: quote, recipient: recipient, sourceAccountID: "acc_sgd", confirmation: confirmation)
    }

    @Test func createSendsTheTransferIDAsTheKeyAndReportsTheStatus() async throws {
        let transport = StubTransport([status(201, transferJSON)])
        let api = RemoteTransferAPI(api: try makeAPI(transport))

        let status = try await api.create(try draft())

        #expect(status == .awaitingConfirmation)
        let request = try #require(await transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == "6f1c2e1a-0000-4000-8000-000000000001")
        #expect(try body(of: request)["recipientId"] as? String == "rcp_1")
    }

    /// The signed bytes go as they are, base64, so the server checks exactly what was signed.
    @Test func confirmPostsTheSignedApproval() async throws {
        let processing = transferJSON.replacingOccurrences(of: "awaiting_confirmation", with: "processing")
        let transport = StubTransport([status(200, processing)])
        let api = RemoteTransferAPI(api: try makeAPI(transport))

        #expect(try await api.confirm(id: id, confirmation: confirmation) == .processing)

        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "/v1/transfers/6f1c2e1a-0000-4000-8000-000000000001/confirm")
        #expect(
            request.value(forHTTPHeaderField: "Idempotency-Key") == "6f1c2e1a-0000-4000-8000-000000000001.confirm")
        let sent = try body(of: request)
        #expect(sent["payload"] as? String == confirmation.payload.base64EncodedString())
        #expect(sent["signature"] as? String == "MEQ=")
        #expect(sent["assertion"] as? String == "ogE=")
    }

    /// Every refusal of the approval is definite: the transfer fails, nothing moved.
    @Test(arguments: [
        ("nonce_expired", TransferFailure.approvalExpired), ("invalid_signature", .notApproved),
        ("payload_mismatch", .notApproved), ("nonce_used", .notApproved), ("device_not_bound", .notApproved),
    ])
    func refusedApprovalFailsTheConfirm(code: String, failure: TransferFailure) async throws {
        let refused = #"{"code":"\#(code)","message":"No","requestId":"r"}"#
        let api = RemoteTransferAPI(api: try makeAPI(StubTransport([status(422, refused)])))

        await #expect(throws: TransferAPIError.rejected(failure)) {
            try await api.confirm(id: id, confirmation: confirmation)
        }
    }

    @Test func failedStatusCarriesTheReason() async throws {
        let failed = transferJSON.replacingOccurrences(
            of: #""status":"awaiting_confirmation""#,
            with: #""status":"failed","failureReason":"insufficient_funds""#
        )
        let api = RemoteTransferAPI(api: try makeAPI(StubTransport([status(200, failed)])))

        #expect(try await api.status(id: id) == .failed(.insufficientFunds))
    }

    /// The recovery rule's inputs: only a definite refusal is a failure.
    @Test(arguments: [
        (APIError.server(status: 409, code: "transfer_exists", message: "", requestID: nil), TransferAPIError.exists),
        (.server(status: 422, code: "idempotency_mismatch", message: "", requestID: nil), .exists),
        (.server(status: 422, code: "quote_expired", message: "", requestID: nil), .rejected(.quoteExpired)),
        (.server(status: 422, code: "insufficient_funds", message: "", requestID: nil), .rejected(.insufficientFunds)),
        (.server(status: 422, code: "declined", message: "", requestID: nil), .rejected(.declined)),
        (.server(status: 404, code: "not_found", message: "", requestID: nil), .notFound),
        (.server(status: 409, code: "idempotency_in_progress", message: "", requestID: nil), .outcomeUnknown),
        (.server(status: 500, code: "internal", message: "", requestID: nil), .outcomeUnknown),
        (.transport(.timedOut), .outcomeUnknown),
        (.transport(.cannotConnectToHost), .outcomeUnknown),
        (.invalidResponse("status"), .outcomeUnknown),
        (.unauthorized, .sessionExpired),
        (.cancelled, .cancelled),
    ])
    func onlyADefiniteRefusalIsAFailure(error: APIError, expected: TransferAPIError) {
        #expect(error.transferAPIError(notFound: .notFound) == expected)
    }

    /// A 404 on create names a missing quote, recipient or account, not a missing transfer.
    @Test func notFoundOnCreateIsARefusal() async throws {
        let transport = StubTransport([status(404, #"{"code":"not_found","message":"","requestId":"r"}"#)])
        let api = RemoteTransferAPI(api: try makeAPI(transport))

        await #expect(throws: TransferAPIError.rejected(.rejected)) {
            try await api.create(try draft())
        }
    }
}

@Suite struct RemoteTransfersRepositoryTests {
    @Test func amountTheServerRefusesIsNotAllowed() async throws {
        let refused = #"{"code":"invalid_request","message":"Amount must be more than the fee.","requestId":"r"}"#
        let repository = RemoteTransfersRepository(api: try makeAPI(StubTransport([status(422, refused)])))

        await #expect(throws: TransferError.amountNotAllowed) {
            try await repository.quote(sourceAmount: Money(amountMinor: 50, currency: .sgd), targetCurrency: .usd)
        }
    }

    @Test(arguments: [
        (HTTPError.transport(.notConnectedToInternet), TransferError.offline),
        (.transport(.cannotConnectToHost), .unavailable),
    ])
    func connectionProblemsSayWhatHappened(error: HTTPError, expected: TransferError) async throws {
        let repository = RemoteTransfersRepository(api: try makeAPI(StubTransport([.failure(error)])))

        await #expect(throws: expected) {
            try await repository.recipients()
        }
    }
}
