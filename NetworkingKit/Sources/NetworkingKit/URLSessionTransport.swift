import Foundation

/// Never follows redirects: the 3xx comes back as the response. URLSession drops
/// `Authorization` on a cross-host redirect but resends the body, which for login and
/// refresh holds the password or refresh token.
///
/// Pins TLS keys per host when given a `PinningPolicy` (ADR-006).
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession
    private let pinning: PinningPolicy?

    /// Pass the session in so the caller owns its configuration (ephemeral cache,
    /// timeouts). Redirects and pinning are handled by a delegate made per request.
    ///
    /// The session must have no delegate of its own: URLSession gives server-trust challenges
    /// to a session delegate first, and pinning would silently stop running.
    public init(session: URLSession, pinning: PinningPolicy? = nil) {
        assert(session.delegate == nil, "a session delegate would take the TLS challenge from the pinning delegate")
        self.session = session
        self.pinning = pinning
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let data: Data
        let response: URLResponse
        let delegate = TaskDelegate(pinning: pinning)
        do {
            (data, response) = try await session.data(for: request, delegate: delegate)
        } catch let error as URLError {
            throw Self.error(for: error.code, pinningFailed: await delegate.outcome.pinningFailed)
        }
        guard let http = response as? HTTPURLResponse else {
            throw HTTPError.invalidResponse
        }
        var headers: [String: String] = [:]
        for case (let name as String, let value as String) in http.allHeaderFields {
            headers[name] = value
        }
        return HTTPResponse(statusCode: http.statusCode, headers: headers, body: data)
    }
}

extension URLSessionTransport {
    /// Rejecting a challenge cancels the task, so URLSession reports a pinning failure as
    /// `URLError.cancelled`, the same as a cancelled task. The delegate remembers which it was.
    static func error(for code: URLError.Code, pinningFailed: Bool) -> any Error {
        if pinningFailed {
            return HTTPError.pinningFailed
        }
        // A cancelled task becomes CancellationError, like any other cancelled work.
        if code == .cancelled {
            return CancellationError()
        }
        return HTTPError.transport(code)
    }
}

/// One per request: refuses every redirect, and checks the server's key for a pinned host.
final class TaskDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let pinning: PinningPolicy?
    let outcome = Outcome()

    /// Whether this request's connection was refused for its key. An actor, so the delegate
    /// stays `Sendable` without locks.
    actor Outcome {
        private(set) var pinningFailed = false

        func markPinningFailed() {
            pinningFailed = true
        }
    }

    init(pinning: PinningPolicy?) {
        self.pinning = pinning
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = space.serverTrust,
            let pinning
        else {
            return (.performDefaultHandling, nil)
        }
        switch pinning.evaluate(trust, host: space.host) {
        case .notPinned:
            return (.performDefaultHandling, nil)
        case .trusted:
            return (.useCredential, URLCredential(trust: trust))
        case .rejected:
            await outcome.markPinningFailed()
            return (.cancelAuthenticationChallenge, nil)
        }
    }
}
