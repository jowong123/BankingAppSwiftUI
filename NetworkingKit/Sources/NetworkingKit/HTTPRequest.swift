import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"

    /// Methods that change server state. They always carry an `Idempotency-Key`.
    public var isMutating: Bool { self != .get }
}

/// Header names the interceptors and servers agree on.
public enum HTTPHeader {
    public static let authorization = "Authorization"
    public static let contentType = "Content-Type"
    public static let accept = "Accept"
    public static let idempotencyKey = "Idempotency-Key"
    public static let requestID = "X-Request-ID"
}

/// A request before it's turned into a `URLRequest`. Interceptors read and change this,
/// so it stays a plain value: easy to compare in tests and safe to pass across tasks.
public struct HTTPRequest: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public var method: HTTPMethod
    /// Relative to the client's base URL, e.g. `/v1/accounts`.
    public var path: String
    public var queryItems: [URLQueryItem]
    public var headers: [String: String]
    public var body: Data?
    /// `false` for calls made without a session (login, refresh). `AuthInterceptor`
    /// leaves them alone, so a 401 from a wrong password doesn't trigger a refresh.
    public var requiresAuthentication: Bool
    /// `false` for calls that must never be sent twice even with an idempotency key, such
    /// as a token refresh the server rotates: a resend would look like a stolen token.
    public var allowsRetry: Bool

    public init(
        method: HTTPMethod,
        path: String,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil,
        requiresAuthentication: Bool = true,
        allowsRetry: Bool = true
    ) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
        self.requiresAuthentication = requiresAuthentication
        self.allowsRetry = allowsRetry
    }

    /// Safe to log or show in a test failure: the `Authorization` value and the body
    /// (which may hold a password or tokens) are never printed.
    public var description: String {
        let headerNames = headers.keys.sorted().map { name in
            name.caseInsensitiveCompare(HTTPHeader.authorization) == .orderedSame ? "\(name): <redacted>" : name
        }
        let bodyText = body.map { "<\($0.count) bytes>" } ?? "none"
        return "\(method.rawValue) \(path) headers: [\(headerNames.joined(separator: ", "))] body: \(bodyText)"
    }

    public var debugDescription: String { description }

    /// `dump`, test-failure diffs and debuggers use the mirror, so it holds only the
    /// redacted description.
    public var customMirror: Mirror {
        Mirror(self, children: ["redacted": description], displayStyle: .struct)
    }

    /// Header lookup ignoring case, as HTTP header names are case-insensitive.
    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// Sets a header, replacing any existing one with the same name in another case.
    public mutating func setHeader(_ name: String, _ value: String) {
        headers = headers.filter { $0.key.caseInsensitiveCompare(name) != .orderedSame }
        headers[name] = value
    }
}

public struct HTTPResponse: Hashable, Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    public var isSuccess: Bool { (200..<300).contains(statusCode) }

    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}
