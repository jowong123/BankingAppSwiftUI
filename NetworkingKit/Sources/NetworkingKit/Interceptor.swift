/// The rest of the chain after an interceptor: the next interceptors, then the transport.
public typealias HTTPNext = @Sendable (HTTPRequest) async throws -> HTTPResponse

/// One link in the client's request pipeline.
///
/// An interceptor can change the request before calling `next`, inspect or replace the
/// response, call `next` more than once (retry), or throw. Interceptors return non-2xx
/// responses rather than throwing, so the ones further out can still react to them;
/// `HTTPClient` turns a final non-2xx into `HTTPError.status`.
public protocol Interceptor: Sendable {
    func intercept(_ request: HTTPRequest, next: HTTPNext) async throws -> HTTPResponse
}
