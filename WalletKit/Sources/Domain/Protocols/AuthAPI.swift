/// Sign-in and token refresh against the server. Declared in Domain so `WalletSecurity`'s
/// `SessionStore` can use it without importing `Networking`; `RemoteAuthAPI` implements it.
public protocol AuthAPI: Sendable {
    /// Checks the password. Returns a binding token, not a session: the session starts when
    /// `bindDevice` binds this device with it.
    func login(email: String, password: String) async throws(AuthError) -> BindingToken

    /// `POST /v1/devices`. Throws `.deviceSetupFailed` if the server refuses the device.
    func bindDevice(_ request: DeviceBindingRequest) async throws(AuthError) -> BoundSession

    /// Refresh tokens rotate: the old one stops working once this succeeds (ADR-016).
    /// Throws `.sessionExpired` when the server refuses the token.
    func refresh(refreshToken: String) async throws(AuthError) -> SessionTokens

    /// Asks the server to revoke the session's tokens. Best effort: the device has already
    /// forgotten them, and if this fails they still expire on the server.
    func logout(refreshToken: String) async throws(AuthError)
}
