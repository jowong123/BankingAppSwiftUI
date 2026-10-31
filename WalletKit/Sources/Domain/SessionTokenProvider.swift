/// Supplies the bearer token for API calls and renews it when the server rejects it.
///
/// Declared in Domain so the session store (Phase 5, backed by `KeychainStore`) can
/// implement it without importing `Networking`, and `Networking` can use it without
/// importing `WalletSecurity`. `AppEnvironment` connects the two.
public protocol SessionTokenProvider: Sendable {
    /// The current access token, or `nil` when there is no session.
    func accessToken() async -> String?

    /// Exchanges the refresh token for a new access token and returns it.
    ///
    /// Throw `SessionRefreshError` when the session is definitely over; the app then
    /// locks it and asks the user to sign in. Errors from `WalletAPI.refresh` can be
    /// rethrown as they are. Any other error (for example the Keychain is unavailable
    /// while the device is locked) is treated as temporary and the session is kept.
    func refreshAccessToken() async throws -> String
}

/// A refresh failure that ends the session.
public enum SessionRefreshError: Error, Hashable, Sendable {
    /// No refresh token is stored: never signed in, signed out, or restored onto a new
    /// device where this-device-only Keychain items don't exist.
    case noSession
    /// The refresh token was refused (expired, revoked or reused).
    case rejected
}
