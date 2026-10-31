import Foundation
import Testing

@testable import NetworkingKit

/// A fake session: holds the token and counts refreshes.
actor FakeSession {
    private(set) var token: String?
    private(set) var refreshCount = 0
    private let refreshedToken: String
    private let refreshError: HTTPError?

    init(token: String?, refreshedToken: String = "new", refreshError: HTTPError? = nil) {
        self.token = token
        self.refreshedToken = refreshedToken
        self.refreshError = refreshError
    }

    func refresh() async throws -> String {
        refreshCount += 1
        // Give concurrent 401s time to pile up behind this refresh.
        try await Task.sleep(for: .milliseconds(50))
        if let refreshError { throw refreshError }
        token = refreshedToken
        return refreshedToken
    }

    var interceptor: AuthInterceptor {
        AuthInterceptor(accessToken: { await self.token }, refresh: { try await self.refresh() })
    }
}

/// 200 for `Bearer new`, 401 for anything else.
func acceptsOnly(_ token: String) -> StubTransport {
    StubTransport { request in
        let authorized = request.value(forHTTPHeaderField: HTTPHeader.authorization) == "Bearer \(token)"
        return HTTPResponse(statusCode: authorized ? 200 : 401)
    }
}

@Suite struct AuthInterceptorTests {
    let request = HTTPRequest(method: .get, path: "/v1/accounts")

    @Test func addsBearerToken() async throws {
        let session = FakeSession(token: "abc")
        let transport = acceptsOnly("abc")
        let client = try makeClient(transport, interceptors: [await session.interceptor])

        #expect(try await client.execute(request).statusCode == 200)
        #expect(await transport.header(HTTPHeader.authorization, at: 0) == "Bearer abc")
        #expect(await session.refreshCount == 0)
    }

    @Test func unauthenticatedRequestsPassThroughUntouched() async throws {
        // A 401 from login means a wrong password, not an expired token.
        let session = FakeSession(token: "abc")
        let transport = StubTransport([status(401)])
        let client = try makeClient(transport, interceptors: [await session.interceptor])
        let login = HTTPRequest(method: .post, path: "/v1/auth/login", requiresAuthentication: false)

        #expect(try await client.execute(login).statusCode == 401)
        #expect(await transport.header(HTTPHeader.authorization, at: 0) == nil)
        #expect(await session.refreshCount == 0)
    }

    @Test func refreshesOnceOn401AndRetriesWithTheNewToken() async throws {
        let session = FakeSession(token: "old")
        let transport = acceptsOnly("new")
        let client = try makeClient(transport, interceptors: [await session.interceptor])

        #expect(try await client.execute(request).statusCode == 200)
        #expect(await session.refreshCount == 1)
        #expect(await transport.header(HTTPHeader.authorization, at: 0) == "Bearer old")
        #expect(await transport.header(HTTPHeader.authorization, at: 1) == "Bearer new")
    }

    @Test func secondUnauthorizedAfterRefreshThrowsInsteadOfLooping() async throws {
        let session = FakeSession(token: "old")
        let transport = StubTransport([status(401)])
        let client = try makeClient(transport, interceptors: [await session.interceptor])

        await #expect(throws: HTTPError.unauthorized) {
            try await client.execute(request)
        }
        #expect(await session.refreshCount == 1)
        #expect(await transport.requests.count == 2)
    }

    @Test(arguments: [400, 401, 403])
    func refreshRejectedByTheServerThrowsUnauthorized(code: Int) async throws {
        let session = FakeSession(token: "old", refreshError: .status(code: code, body: Data()))
        let transport = acceptsOnly("new")
        let client = try makeClient(transport, interceptors: [await session.interceptor])

        await #expect(throws: HTTPError.unauthorized) {
            try await client.execute(request)
        }
        #expect(await transport.requests.count == 1)
    }

    @Test func concurrent401sShareOneRefresh() async throws {
        // Refresh tokens rotate: a second parallel refresh would be rejected and log the user out.
        let session = FakeSession(token: "old")
        let transport = acceptsOnly("new")
        let client = try makeClient(transport, interceptors: [await session.interceptor])
        let request = request

        let codes = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<8 {
                group.addTask { try await client.execute(request).statusCode }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        #expect(codes == Array(repeating: 200, count: 8))
        #expect(await session.refreshCount == 1)
    }

    @Test(arguments: [
        HTTPError.transport(.notConnectedToInternet), .transport(.timedOut),
        .status(code: 408, body: Data()), .status(code: 429, body: Data()),
        .status(code: 502, body: Data()), .status(code: 503, body: Data()),
    ])
    func refreshThatFailsForNetworkReasonsDoesNotLockTheSession(error: HTTPError) async throws {
        // Offline or rate limited is not "signed out": the caller sees the error and can retry later.
        let session = FakeSession(token: "old", refreshError: error)
        let client = try makeClient(acceptsOnly("new"), interceptors: [await session.interceptor])

        await #expect(throws: error) {
            try await client.execute(request)
        }
    }

    @Test func noSessionYetStillRefreshesOnce() async throws {
        let session = FakeSession(token: nil)
        let transport = acceptsOnly("new")
        let client = try makeClient(transport, interceptors: [await session.interceptor])

        #expect(try await client.execute(request).statusCode == 200)
        #expect(await transport.header(HTTPHeader.authorization, at: 0) == nil)
        #expect(await session.refreshCount == 1)
    }
}
