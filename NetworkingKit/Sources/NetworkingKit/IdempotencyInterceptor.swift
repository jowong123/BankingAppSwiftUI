import Foundation

/// Gives every mutating request an `Idempotency-Key`, keeping one the caller already set.
///
/// The key is created here, once per call, and this interceptor sits outside
/// `RetryInterceptor`. So every retry of a POST sends the same key, and the server
/// returns the original response instead of doing the work twice. Callers that need the
/// key to survive an app restart (a transfer uses its own ID) set it themselves.
public struct IdempotencyInterceptor: Interceptor {
    private let makeKey: @Sendable () -> String

    public init(makeKey: @escaping @Sendable () -> String = { UUID().uuidString }) {
        self.makeKey = makeKey
    }

    public func intercept(_ request: HTTPRequest, next: HTTPNext) async throws -> HTTPResponse {
        guard request.method.isMutating, request.header(HTTPHeader.idempotencyKey) == nil else {
            return try await next(request)
        }
        var request = request
        request.setHeader(HTTPHeader.idempotencyKey, makeKey())
        return try await next(request)
    }
}
