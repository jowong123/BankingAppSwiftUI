import Foundation

public enum HTTPError: Error, Hashable, Sendable {
    /// No HTTP response arrived (timeout, offline, connection lost).
    ///
    /// For a mutating request the outcome is **unknown**: the server may have processed it.
    /// Callers must not treat this as a failure; retry with the same `Idempotency-Key`
    /// or check status first (CLAUDE.md, SPEC section 5).
    case transport(URLError.Code)
    /// The server answered with a non-2xx status. `body` is kept so the caller can
    /// decode its own error envelope.
    case status(code: Int, body: Data)
    /// 401 that a token refresh couldn't fix. The session should lock.
    case unauthorized
    /// The 2xx body didn't match the expected type. Holds the coding path only, never
    /// values, so it can be logged without leaking response data.
    case decoding(path: String)
    /// The request couldn't be turned into a URL, or the response wasn't HTTP.
    case invalidRequest
    case invalidResponse
}
