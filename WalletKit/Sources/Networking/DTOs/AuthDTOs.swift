import Foundation

struct LoginRequestDTO: Encodable, Sendable, CustomStringConvertible, CustomReflectable {
    let email: String
    let password: String

    var description: String {
        "LoginRequestDTO(<redacted>)"
    }
    var customMirror: Mirror {
        Mirror(self, children: [:])
    }
}

struct RefreshRequestDTO: Encodable, Sendable, CustomStringConvertible, CustomReflectable {
    let refreshToken: String

    var description: String {
        "RefreshRequestDTO(<redacted>)"
    }
    var customMirror: Mirror {
        Mirror(self, children: [:])
    }
}

struct LogoutRequestDTO: Encodable, Sendable, CustomStringConvertible, CustomReflectable {
    let refreshToken: String

    var description: String {
        "LogoutRequestDTO(<redacted>)"
    }
    var customMirror: Mirror {
        Mirror(self, children: [:])
    }
}

/// Tokens from login and refresh. `RemoteAuthAPI` turns them into `SessionTokens`, which
/// go straight to the Keychain. Redacted so an accidental log or crash report can't leak them.
struct SessionTokensDTO: Decodable, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    let accessToken: String
    let refreshToken: String
    /// Access-token lifetime in seconds.
    let expiresIn: Int

    var description: String {
        "SessionTokensDTO(<redacted>)"
    }
    var debugDescription: String {
        description
    }
    /// Empty, so `dump`, debuggers and test-failure diffs can't print the tokens either.
    var customMirror: Mirror {
        Mirror(self, children: [:])
    }
}
