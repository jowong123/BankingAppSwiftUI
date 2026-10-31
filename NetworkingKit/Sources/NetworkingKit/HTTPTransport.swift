import Foundation

/// Sends one fully built request and returns the raw response, whatever its status.
/// The seam between the interceptor chain and the network, so tests can replace it.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

/// Never follows redirects: the 3xx comes back as the response. URLSession drops
/// `Authorization` on a cross-host redirect but resends the body, which for login and
/// refresh holds the password or refresh token.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession
    private let redirects = RefuseRedirects()

    /// Pass the session in so the caller owns its configuration (ephemeral cache,
    /// timeouts, and in Phase 7 the delegate that does TLS pinning, ADR-006). Redirects
    /// are refused by a per-task delegate, so the session delegate stays free for pinning.
    public init(session: URLSession) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: redirects)
        } catch let error as URLError {
            // URLSession reports task cancellation as URLError.cancelled. Surface it as
            // CancellationError so callers handle it like any other cancelled work.
            if error.code == .cancelled { throw CancellationError() }
            throw HTTPError.transport(error.code)
        }
        guard let http = response as? HTTPURLResponse else { throw HTTPError.invalidResponse }
        var headers: [String: String] = [:]
        for case (let name as String, let value as String) in http.allHeaderFields {
            headers[name] = value
        }
        return HTTPResponse(statusCode: http.statusCode, headers: headers, body: data)
    }
}

/// Answers every redirect with "don't follow". Stateless, so sharing it across tasks is safe.
final class RefuseRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
