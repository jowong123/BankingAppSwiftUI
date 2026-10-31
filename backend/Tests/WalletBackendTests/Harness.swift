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
        if let token { headers.bearerAuthorization = BearerAuthorization(token: token) }
        var body = ByteBuffer()
        if let json {
            headers.contentType = .json
            body = ByteBuffer(data: try JSONEncoder().encode(json))
        }
        let request = XCTHTTPRequest(method: method, url: URI(path: path), headers: headers, body: body)
        return try await app.testable().performTest(request: request)
    }

    func login(email: String = Sandbox.demoEmail, password: String = Sandbox.demoPassword) async throws
        -> SessionTokens
    {
        let response = try await send(.POST, "/v1/auth/login", json: LoginRequest(email: email, password: password))
        XCTAssertEqual(response.status, .ok)
        return try response.content.decode(SessionTokens.self)
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

func withApp(simulation: Bool = true, _ test: (Harness) async throws -> Void) async throws {
    let app = try await Application.make(.testing)
    let (clock, advance) = BackendClock.manual(start: Harness.start)
    let environment = BackendEnvironment(
        database: .init(storage: .memory),
        clock: clock,
        rates: .fixed,
        bcryptCost: 4,
        simulationEnabled: simulation
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
    var envelope: ErrorEnvelope? { try? content.decode(ErrorEnvelope.self) }
}

extension ErrorEnvelope: Equatable {
    public static func == (lhs: ErrorEnvelope, rhs: ErrorEnvelope) -> Bool {
        lhs.code == rhs.code && lhs.message == rhs.message && lhs.requestId == rhs.requestId
    }
}
