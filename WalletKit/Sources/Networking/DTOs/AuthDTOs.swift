import Foundation

struct LoginRequestDTO: Encodable, Sendable, CustomStringConvertible, CustomReflectable {
    let email: String
    let password: String

    var description: String { "LoginRequestDTO(<redacted>)" }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct RefreshRequestDTO: Encodable, Sendable, CustomStringConvertible, CustomReflectable {
    let refreshToken: String

    var description: String { "RefreshRequestDTO(<redacted>)" }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Tokens from login and refresh. They go straight to the Keychain (Phase 5).
/// The descriptions are redacted so an accidental log or crash report can't leak them.
public struct SessionTokensDTO: Decodable, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public let accessToken: String
    public let refreshToken: String
    /// Access-token lifetime in seconds.
    public let expiresIn: Int

    public var description: String { "SessionTokensDTO(<redacted>)" }
    public var debugDescription: String { description }
    /// Empty, so `dump`, debuggers and test-failure diffs can't print the tokens either.
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}
