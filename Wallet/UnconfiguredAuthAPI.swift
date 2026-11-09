import Domain

/// Used only if the build has no valid `WalletAPIBaseURL`: sign-in reports the service as
/// unavailable, so a misconfigured build fails closed instead of guessing a server.
struct UnconfiguredAuthAPI: AuthAPI {
    func login(email: String, password: String) async throws(AuthError) -> SessionTokens {
        throw .unavailable
    }

    func refresh(refreshToken: String) async throws(AuthError) -> SessionTokens {
        throw .unavailable
    }

    func logout(refreshToken: String) async throws(AuthError) {
        throw .unavailable
    }
}
