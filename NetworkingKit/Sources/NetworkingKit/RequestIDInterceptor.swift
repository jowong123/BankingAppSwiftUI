import Foundation

/// Adds an `X-Request-ID` unless the request already has one.
///
/// It runs outermost, so retries of one call share the ID: support can find every
/// attempt in the server logs from the ID in a user's error report.
public struct RequestIDInterceptor: Interceptor {
    private let makeID: @Sendable () -> String

    public init(makeID: @escaping @Sendable () -> String = { UUID().uuidString }) {
        self.makeID = makeID
    }

    public func intercept(_ request: HTTPRequest, next: HTTPNext) async throws -> HTTPResponse {
        guard request.header(HTTPHeader.requestID) == nil else { return try await next(request) }
        var request = request
        request.setHeader(HTTPHeader.requestID, makeID())
        return try await next(request)
    }
}
