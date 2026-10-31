import Foundation
import Testing

@testable import NetworkingKit

actor EventLog {
    private(set) var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }
}

struct LoggingInterceptor: Interceptor {
    let name: String
    let log: EventLog

    func intercept(_ request: HTTPRequest, next: HTTPNext) async throws -> HTTPResponse {
        await log.append("\(name) in")
        let response = try await next(request)
        await log.append("\(name) out")
        return response
    }
}

@Suite struct HTTPClientTests {
    @Test func firstInterceptorIsOutermost() async throws {
        let log = EventLog()
        let transport = StubTransport([status(200)])
        let client = try makeClient(
            transport,
            interceptors: [LoggingInterceptor(name: "a", log: log), LoggingInterceptor(name: "b", log: log)]
        )

        _ = try await client.execute(HTTPRequest(method: .get, path: "/v1/accounts"))

        #expect(await log.events == ["a in", "b in", "b out", "a out"])
    }

    @Test func buildsURLRequestFromPathQueryHeadersAndBody() throws {
        let request = HTTPRequest(
            method: .post,
            path: "/v1/accounts/acc_1/transactions",
            queryItems: [URLQueryItem(name: "cursor", value: "abc"), URLQueryItem(name: "limit", value: "20")],
            headers: ["Accept": "application/json"],
            body: Data("{}".utf8)
        )

        let urlRequest = try HTTPClient.urlRequest(for: request, baseURL: try requireBaseURL())

        #expect(
            urlRequest.url?.absoluteString
                == "https://api.example.test/v1/accounts/acc_1/transactions?cursor=abc&limit=20"
        )
        #expect(urlRequest.httpMethod == "POST")
        #expect(urlRequest.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(urlRequest.httpBody == Data("{}".utf8))
    }

    @Test func neverUsesTheURLCache() throws {
        let urlRequest = try HTTPClient.urlRequest(
            for: HTTPRequest(method: .get, path: "/v1/accounts"),
            baseURL: try requireBaseURL()
        )

        #expect(urlRequest.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
    }

    @Test func printingARequestRedactsTheTokenAndBody() {
        let request = HTTPRequest(
            method: .post,
            path: "/v1/auth/login",
            headers: [HTTPHeader.authorization: "Bearer secret-token"],
            body: Data(#"{"password":"hunter2"}"#.utf8)
        )

        for text in [
            "\(request)", String(reflecting: request),
            String(describing: Mirror(reflecting: request).children.map(\.value)),
        ] {
            #expect(!text.contains("secret-token"))
            #expect(!text.contains("hunter2"))
        }
        #expect("\(request)".contains("Authorization: <redacted>"))
    }

    @Test func decodesSuccessfulBody() async throws {
        let client = try makeClient(StubTransport([status(200, #"{"id":"acc_1"}"#)]), interceptors: [])
        let endpoint = Endpoint<Account>(request: HTTPRequest(method: .get, path: "/v1/accounts/acc_1"))

        #expect(try await client.send(endpoint) == Account(id: "acc_1"))
    }

    @Test func nonSuccessStatusThrowsWithBodyForTheCallerToDecode() async throws {
        let body = #"{"code":"quote_expired"}"#
        let client = try makeClient(StubTransport([status(422, body)]), interceptors: [])
        let endpoint = Endpoint<Account>(request: HTTPRequest(method: .get, path: "/v1/accounts/acc_1"))

        await #expect(throws: HTTPError.status(code: 422, body: Data(body.utf8))) {
            try await client.send(endpoint)
        }
    }

    @Test func decodingErrorReportsThePathButNoValues() async throws {
        let client = try makeClient(StubTransport([status(200, #"{"id":12345}"#)]), interceptors: [])
        let endpoint = Endpoint<Account>(request: HTTPRequest(method: .get, path: "/v1/accounts/acc_1"))

        await #expect(throws: HTTPError.decoding(path: "id")) {
            try await client.send(endpoint)
        }
    }
}

/// The Phase 3 "done when" check: a retried POST reuses the same idempotency key.
@Suite struct StandardChainTests {
    @Test func retriedPostReusesTheSameIdempotencyKeyAndRequestID() async throws {
        let transport = StubTransport([status(503), .failure(.transport(.timedOut)), status(201)])
        let client = try makeClient(
            transport, interceptors: HTTPClient.standardInterceptors(auth: nil, retry: instantRetry()))

        let response = try await client.execute(HTTPRequest(method: .post, path: "/v1/transfers"))

        #expect(response.statusCode == 201)
        let requests = await transport.requests
        #expect(requests.count == 3)
        let keys = Set(requests.map { $0.value(forHTTPHeaderField: HTTPHeader.idempotencyKey) })
        let requestIDs = Set(requests.map { $0.value(forHTTPHeaderField: HTTPHeader.requestID) })
        #expect(keys.count == 1)
        #expect(keys.first.flatMap(\.self) != nil)
        #expect(requestIDs.count == 1)
        #expect(requestIDs.first.flatMap(\.self) != nil)
    }

    @Test func callerSuppliedKeyIsKeptAcrossRetries() async throws {
        // A transfer uses its own ID as the key, so it survives an app restart.
        let transport = StubTransport([status(500), status(201)])
        let client = try makeClient(
            transport, interceptors: HTTPClient.standardInterceptors(auth: nil, retry: instantRetry()))
        let request = HTTPRequest(
            method: .post,
            path: "/v1/transfers",
            headers: [HTTPHeader.idempotencyKey: "trf_42"]
        )

        _ = try await client.execute(request)

        #expect(await transport.header(HTTPHeader.idempotencyKey, at: 0) == "trf_42")
        #expect(await transport.header(HTTPHeader.idempotencyKey, at: 1) == "trf_42")
    }

    @Test func separateCallsGetDifferentKeys() async throws {
        let transport = StubTransport([status(201)])
        let client = try makeClient(transport, interceptors: HTTPClient.standardInterceptors(auth: nil))

        _ = try await client.execute(HTTPRequest(method: .post, path: "/v1/quotes"))
        _ = try await client.execute(HTTPRequest(method: .post, path: "/v1/quotes"))

        let first = await transport.header(HTTPHeader.idempotencyKey, at: 0)
        let second = await transport.header(HTTPHeader.idempotencyKey, at: 1)
        #expect(first != nil)
        #expect(first != second)
    }
}

@Suite struct HeaderInterceptorTests {
    @Test func getHasRequestIDButNoIdempotencyKey() async throws {
        let transport = StubTransport([status(200)])
        let client = try makeClient(transport, interceptors: HTTPClient.standardInterceptors(auth: nil))

        _ = try await client.execute(HTTPRequest(method: .get, path: "/v1/accounts"))

        #expect(await transport.header(HTTPHeader.requestID, at: 0) != nil)
        #expect(await transport.header(HTTPHeader.idempotencyKey, at: 0) == nil)
    }

    @Test(arguments: [HTTPMethod.post, .put, .patch, .delete])
    func everyMutatingMethodGetsAKey(method: HTTPMethod) async throws {
        let transport = StubTransport([status(200)])
        let client = try makeClient(transport, interceptors: [IdempotencyInterceptor(makeKey: { "key_1" })])

        _ = try await client.execute(HTTPRequest(method: method, path: "/v1/things"))

        #expect(await transport.header(HTTPHeader.idempotencyKey, at: 0) == "key_1")
    }

    @Test func existingHeadersAreMatchedCaseInsensitively() async throws {
        let transport = StubTransport([status(200)])
        let client = try makeClient(
            transport,
            interceptors: [RequestIDInterceptor(makeID: { "new" }), IdempotencyInterceptor(makeKey: { "new" })]
        )
        let request = HTTPRequest(
            method: .post,
            path: "/v1/transfers",
            headers: ["idempotency-key": "mine", "x-request-id": "mine-too"]
        )

        _ = try await client.execute(request)

        let sent = try #require(await transport.requests.first)
        #expect(sent.value(forHTTPHeaderField: HTTPHeader.idempotencyKey) == "mine")
        #expect(sent.value(forHTTPHeaderField: HTTPHeader.requestID) == "mine-too")
    }
}
