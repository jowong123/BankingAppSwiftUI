import Crypto
import FluentSQLiteDriver
import XCTVapor

@testable import WalletBackend

/// A fresh app with an in-memory database, fixed FX rates and a clock the test moves.
struct Harness {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    let app: Application
    let advance: @Sendable (TimeInterval) -> Void

    /// Sends a request and returns the response. Errors propagate instead of calling
    /// `XCTFail`, so a test can assert on a dropped connection.
    func send(
        _ method: HTTPMethod,
        _ path: String,
        token: String? = nil,
        headers: HTTPHeaders = [:],
        json: (any Encodable)? = nil
    ) async throws -> XCTHTTPResponse {
        var headers = headers
        if let token {
            headers.bearerAuthorization = BearerAuthorization(token: token)
        }
        var body = ByteBuffer()
        if let json {
            headers.contentType = .json
            // Sorted, so a test that sends the same body twice sends the same bytes. This
            // Foundation's encoder doesn't keep key order stable between calls.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            body = ByteBuffer(data: try encoder.encode(json))
        }
        let request = XCTHTTPRequest(method: method, url: URI(path: path), headers: headers, body: body)
        return try await app.testable().performTest(request: request)
    }

    /// Signs in and binds a new device with a software P-256 key standing in for the Secure
    /// Enclave (sandbox attestation mode).
    func login(email: String = Sandbox.demoEmail, password: String = Sandbox.demoPassword) async throws
        -> SignedIn
    {
        let key = P256.Signing.PrivateKey()
        let response = try await bind(
            DeviceBindingRequest(
                bindingToken: try await bindingToken(email: email, password: password),
                signingKey: key.publicKey.x963Representation.base64EncodedString(),
                attestation: nil
            )
        )
        XCTAssertEqual(response.status, .ok)
        let bound = try response.content.decode(BoundDevice.self)
        return SignedIn(
            accessToken: bound.accessToken,
            refreshToken: bound.refreshToken,
            expiresIn: bound.expiresIn,
            deviceId: bound.deviceId,
            key: key
        )
    }

    func bindingToken(email: String = Sandbox.demoEmail, password: String = Sandbox.demoPassword) async throws
        -> String
    {
        let response = try await send(.POST, "/v1/auth/login", json: LoginRequest(email: email, password: password))
        XCTAssertEqual(response.status, .ok)
        return try response.content.decode(BindingTokenResponse.self).bindingToken
    }

    func bind(_ request: DeviceBindingRequest) async throws -> XCTHTTPResponse {
        try await send(.POST, "/v1/devices", json: request)
    }

    /// Gets a challenge for `id` (the transfer's own unless given), signs the payload for
    /// `transfer` with the session's key, and confirms. A refused challenge is returned as is.
    func confirm(_ session: SignedIn, _ transfer: TransferDTO, id: String? = nil) async throws -> XCTHTTPResponse {
        let transferID = id ?? transfer.id
        let challenge = try await send(.POST, "/v1/transfers/\(transferID)/challenge", token: session.accessToken)
        guard challenge.status == .created else {
            return challenge
        }
        let nonce = try challenge.content.decode(ChallengeDTO.self).nonce
        return try await sendConfirm(
            session, id: transferID, payload: payload(for: transfer, id: transferID, nonce: nonce))
    }

    func payload(for transfer: TransferDTO, id: String? = nil, nonce: String) -> ConfirmPayload {
        ConfirmPayload(
            transferId: id ?? transfer.id,
            amountMinor: transfer.sourceAmount.amountMinor,
            currency: transfer.sourceAmount.currency,
            recipientId: transfer.recipientId,
            quoteId: transfer.quoteId,
            nonce: nonce,
            timestamp: Int64(Self.start.timeIntervalSince1970 * 1000)
        )
    }

    /// Signs `payload` (with `key`, or the session's) and posts it.
    func sendConfirm(
        _ session: SignedIn,
        id: String,
        payload: ConfirmPayload,
        key: P256.Signing.PrivateKey? = nil,
        assertion: String? = nil
    ) async throws -> XCTHTTPResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        let signature = try (key ?? session.key).signature(for: data)
        return try await send(
            .POST,
            "/v1/transfers/\(id)/confirm",
            token: session.accessToken,
            json: ConfirmRequest(
                payload: data.base64EncodedString(),
                signature: signature.derRepresentation.base64EncodedString(),
                assertion: assertion
            )
        )
    }

    func quote(token: String, minor: Int64 = 10_000, from source: String = "SGD", to target: String = "USD")
        async throws -> QuoteDTO
    {
        let response = try await send(
            .POST,
            "/v1/quotes",
            token: token,
            json: QuoteRequest(sourceAmount: MoneyDTO(amountMinor: minor, currency: source), targetCurrency: target)
        )
        XCTAssertEqual(response.status, .created)
        return try response.content.decode(QuoteDTO.self)
    }
}

/// A bound session, with the key that signs its confirms.
struct SignedIn {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int64
    let deviceId: String
    let key: P256.Signing.PrivateKey
}

func withApp(
    simulation: Bool = true,
    attestation: AttestationMode = .sandbox,
    _ test: (Harness) async throws -> Void
) async throws {
    let app = try await Application.make(.testing)
    let (clock, advance) = BackendClock.manual(start: Harness.start)
    let environment = BackendEnvironment(
        database: .init(storage: .memory),
        clock: clock,
        rates: .fixed,
        bcryptCost: 4,
        simulationEnabled: simulation,
        attestation: attestation
    )
    do {
        try await configure(app, environment: environment)
        try await test(Harness(app: app, advance: advance))
    } catch {
        try await app.asyncShutdown()
        throw error
    }
    try await app.asyncShutdown()
}

extension XCTHTTPResponse {
    var envelope: ErrorEnvelope? {
        try? content.decode(ErrorEnvelope.self)
    }
}

extension ErrorEnvelope: Equatable {
    public static func == (lhs: ErrorEnvelope, rhs: ErrorEnvelope) -> Bool {
        lhs.code == rhs.code && lhs.message == rhs.message && lhs.requestId == rhs.requestId
    }
}
