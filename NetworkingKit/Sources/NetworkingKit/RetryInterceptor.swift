import Foundation

public struct RetryPolicy: Hashable, Sendable {
    /// Total attempts including the first, so 3 means at most 2 retries.
    public var maxAttempts: Int
    /// The backoff cap for the first retry. It doubles for each retry after that.
    public var baseDelay: Duration
    public var maxDelay: Duration

    public init(maxAttempts: Int = 3, baseDelay: Duration = .milliseconds(500), maxDelay: Duration = .seconds(8)) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    /// Full jitter: a random delay between zero and `min(maxDelay, baseDelay * 2^(retry - 1))`.
    /// Random spread stops many clients that failed together from retrying together.
    /// `retry` starts at 1; `unitRandom` is in `0..<1`.
    func delay(beforeRetry retry: Int, unitRandom: Double) -> Duration {
        let exponential = baseDelay * (1 << min(retry - 1, 30))
        let cap = min(exponential, maxDelay)
        return .seconds(cap.seconds * unitRandom)
    }
}

/// Retries transient transport errors, 5xx and 429 with exponential backoff and full jitter.
///
/// - Only transport errors where the network failed are retried (offline, timeout,
///   connection lost, DNS). TLS, certificate, ATS and bad-URL errors fail the same way
///   every time, and a Phase 7 pinning failure must surface at once, not after 3 attempts.
/// - A mutating request is retried only if it has an `Idempotency-Key`; without one a
///   retry could repeat the side effect. `IdempotencyInterceptor` runs outside this one,
///   so in the standard chain every POST has a key, the same one on every attempt.
/// - A request with `allowsRetry == false` (token refresh) is never retried.
/// - 4xx other than 429 is never retried: sending the same request again won't help.
/// - Cancellation stops the loop, including during the backoff sleep.
public struct RetryInterceptor: Interceptor {
    public let policy: RetryPolicy
    private let sleep: @Sendable (Duration) async throws -> Void
    private let unitRandom: @Sendable () -> Double

    public init(
        policy: RetryPolicy = RetryPolicy(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        unitRandom: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }
    ) {
        self.policy = policy
        self.sleep = sleep
        self.unitRandom = unitRandom
    }

    public func intercept(_ request: HTTPRequest, next: HTTPNext) async throws -> HTTPResponse {
        let canRetry =
            request.allowsRetry
            && (!request.method.isMutating || request.header(HTTPHeader.idempotencyKey) != nil)
        var attempt = 1
        while true {
            try Task.checkCancellation()
            do {
                let response = try await next(request)
                guard canRetry, attempt < policy.maxAttempts, Self.isRetryable(status: response.statusCode) else {
                    return response
                }
            } catch HTTPError.transport(let code) {
                guard canRetry, attempt < policy.maxAttempts, Self.isRetryable(transport: code) else {
                    throw HTTPError.transport(code)
                }
            }
            try await sleep(policy.delay(beforeRetry: attempt, unitRandom: unitRandom()))
            attempt += 1
        }
    }

    static func isRetryable(status: Int) -> Bool {
        status == 429 || (500..<600).contains(status)
    }

    /// An allow-list, so a transport error nobody thought about is not retried.
    static let retryableTransportCodes: Set<URLError.Code> = [
        .timedOut, .networkConnectionLost, .notConnectedToInternet,
        .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
    ]

    static func isRetryable(transport code: URLError.Code) -> Bool {
        retryableTransportCodes.contains(code)
    }
}

extension Duration {
    fileprivate var seconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}
