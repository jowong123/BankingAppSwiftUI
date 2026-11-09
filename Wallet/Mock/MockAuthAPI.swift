#if DEBUG
    import Domain

    /// Sign-in for UI tests (`-mockServer`). Any email works; the password "wrong" is refused,
    /// so tests can see the error. Debug only; no real credentials anywhere.
    struct MockAuthAPI: AuthAPI {
        func login(email: String, password: String) async throws(AuthError) -> SessionTokens {
            guard password != "wrong" else {
                throw .invalidCredentials
            }
            return SessionTokens(accessToken: "mock-access", refreshToken: "mock-refresh")
        }

        func refresh(refreshToken: String) async throws(AuthError) -> SessionTokens {
            SessionTokens(accessToken: "mock-access", refreshToken: "mock-refresh")
        }

        func logout(refreshToken: String) async throws(AuthError) {}
    }
#endif
