/// The access and refresh tokens for a signed-in user. They live only in the Keychain
/// (SPEC section 6). Printing, dumping or mirroring this value never shows them.
public struct SessionTokens: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public let accessToken: String
    public let refreshToken: String

    public init(accessToken: String, refreshToken: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }

    public var description: String {
        "SessionTokens(<redacted>)"
    }
    public var debugDescription: String {
        description
    }
    public var customMirror: Mirror {
        Mirror(self, children: [:])
    }
}
