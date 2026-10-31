import Foundation
import Testing

@testable import NetworkingKit

@Suite struct RetryInterceptorTests {
    let get = HTTPRequest(method: .get, path: "/v1/accounts")
    let keyedPost = HTTPRequest(method: .post, path: "/v1/transfers", headers: [HTTPHeader.idempotencyKey: "k"])

    @Test func getIsRetriedAfterTransportErrorThenSucceeds() async throws {
        let transport = StubTransport([.failure(.transport(.networkConnectionLost)), status(200)])
        let client = try makeClient(transport, interceptors: [instantRetry()])

        let response = try await client.execute(get)

        #expect(response.statusCode == 200)
        #expect(await transport.requests.count == 2)
    }

    @Test(arguments: [500, 502, 503, 504, 429])
    func retryableStatusesAreRetried(code: Int) async throws {
        let transport = StubTransport([status(code), status(200)])
        let client = try makeClient(transport, interceptors: [instantRetry()])

        #expect(try await client.execute(get).statusCode == 200)
        #expect(await transport.requests.count == 2)
    }

    @Test(arguments: [400, 401, 403, 404, 409, 422])
    func clientErrorsAreNotRetried(code: Int) async throws {
        let transport = StubTransport([status(code), status(200)])
        let client = try makeClient(transport, interceptors: [instantRetry()])

        #expect(try await client.execute(keyedPost).statusCode == code)
        #expect(await transport.requests.count == 1)
    }

    @Test func stopsAfterMaxAttemptsAndReturnsTheLastResponse() async throws {
        let transport = StubTransport([status(503)])
        let client = try makeClient(transport, interceptors: [instantRetry()])

        #expect(try await client.execute(get).statusCode == 503)
        #expect(await transport.requests.count == 3)
    }

    @Test func rethrowsTransportErrorAfterMaxAttempts() async throws {
        let transport = StubTransport([.failure(.transport(.timedOut))])
        let client = try makeClient(transport, interceptors: [instantRetry()])

        await #expect(throws: HTTPError.transport(.timedOut)) {
            try await client.execute(keyedPost)
        }
        #expect(await transport.requests.count == 3)
    }

    @Test(arguments: [
        URLError.Code.timedOut, .networkConnectionLost, .notConnectedToInternet,
        .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
    ])
    func transientTransportErrorsAreRetried(code: URLError.Code) async throws {
        let transport = StubTransport([.failure(.transport(code)), status(200)])
        let client = try makeClient(transport, interceptors: [instantRetry()])

        #expect(try await client.execute(get).statusCode == 200)
        #expect(await transport.requests.count == 2)
    }

    @Test(arguments: [
        URLError.Code.serverCertificateUntrusted, .secureConnectionFailed,
        .appTransportSecurityRequiresSecureConnection, .badURL, .unsupportedURL,
    ])
    func transportErrorsThatWouldFailAgainAreNotRetried(code: URLError.Code) async throws {
        // A pinning or TLS failure must reach the caller at once, not after three attempts.
        let transport = StubTransport([.failure(.transport(code)), status(200)])
        let client = try makeClient(transport, interceptors: [instantRetry()])

        await #expect(throws: HTTPError.transport(code)) {
            try await client.execute(get)
        }
        #expect(await transport.requests.count == 1)
    }

    @Test func postWithoutIdempotencyKeyIsNeverRetried() async throws {
        // Without a key the server can't tell a retry from a second transfer.
        let transport = StubTransport([.failure(.transport(.timedOut)), status(201)])
        let client = try makeClient(transport, interceptors: [instantRetry()])

        await #expect(throws: HTTPError.transport(.timedOut)) {
            try await client.execute(HTTPRequest(method: .post, path: "/v1/transfers"))
        }
        #expect(await transport.requests.count == 1)
    }

    @Test func postWithIdempotencyKeyIsRetried() async throws {
        let transport = StubTransport([.failure(.transport(.timedOut)), status(201)])
        let client = try makeClient(transport, interceptors: [instantRetry()])

        #expect(try await client.execute(keyedPost).statusCode == 201)
        #expect(await transport.requests.count == 2)
    }

    @Test func backoffDoublesFromHalfASecond() async throws {
        let recorder = SleepRecorder()
        let transport = StubTransport([status(503)])
        let client = try makeClient(transport, interceptors: [instantRetry(recorder, maxAttempts: 4)])

        _ = try await client.execute(get)

        #expect(await recorder.delays == [.milliseconds(500), .seconds(1), .seconds(2)])
    }

    @Test func backoffIsCappedAtMaxDelay() {
        let policy = RetryPolicy(maxAttempts: 10, baseDelay: .milliseconds(500), maxDelay: .seconds(2))

        let delays = (1...5).map { policy.delay(beforeRetry: $0, unitRandom: 1) }

        #expect(delays == [.milliseconds(500), .seconds(1), .seconds(2), .seconds(2), .seconds(2)])
    }

    @Test(arguments: [0.0, 0.25, 0.5])
    func fullJitterScalesTheWholeDelay(random: Double) {
        let policy = RetryPolicy()

        #expect(policy.delay(beforeRetry: 2, unitRandom: random) == .seconds(random))
    }

    @Test func cancellationDuringBackoffStopsRetrying() async throws {
        let transport = StubTransport([status(503)])
        let (sleeping, signal) = AsyncStream<Void>.makeStream()
        let retry = RetryInterceptor(
            sleep: { _ in
                signal.yield()
                try await Task.sleep(for: .seconds(60))
            },
            unitRandom: { 1 }
        )
        let client = try makeClient(transport, interceptors: [retry])
        let request = get

        let task = Task { try await client.execute(request) }
        for await _ in sleeping { break }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(await transport.requests.count == 1)
    }

    @Test func requestThatOptsOutIsNeverRetriedEvenWithAKey() async throws {
        // A rotated refresh token resent after a lost response would look like theft.
        let transport = StubTransport([.failure(.transport(.timedOut)), status(200)])
        let client = try makeClient(transport, interceptors: [instantRetry()])
        let refresh = HTTPRequest(
            method: .post,
            path: "/v1/auth/refresh",
            headers: [HTTPHeader.idempotencyKey: "k"],
            allowsRetry: false
        )

        await #expect(throws: HTTPError.transport(.timedOut)) {
            try await client.execute(refresh)
        }
        #expect(await transport.requests.count == 1)
    }
}
