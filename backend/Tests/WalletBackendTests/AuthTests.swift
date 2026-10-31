import XCTVapor

@testable import WalletBackend

final class AuthTests: XCTestCase {
    func testLoginReturnsWorkingTokens() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()

            XCTAssertEqual(tokens.expiresIn, 900)
            XCTAssertNotEqual(tokens.accessToken, tokens.refreshToken)
            let accounts = try await harness.send(.GET, "/v1/accounts", token: tokens.accessToken)
            XCTAssertEqual(accounts.status, .ok)
        }
    }

    func testEmailIsCaseAndWhitespaceInsensitive() async throws {
        try await withApp { harness in
            _ = try await harness.login(email: "  Demo@Wallet.TEST ")
        }
    }

    func testWrongPasswordAndUnknownEmailGiveTheSameError() async throws {
        try await withApp { harness in
            let wrong = try await harness.send(
                .POST,
                "/v1/auth/login",
                json: LoginRequest(email: Sandbox.demoEmail, password: "nope")
            )
            let unknown = try await harness.send(
                .POST,
                "/v1/auth/login",
                json: LoginRequest(email: "nobody@wallet.test", password: "nope")
            )

            XCTAssertEqual(wrong.status, .unauthorized)
            XCTAssertEqual(unknown.status, .unauthorized)
            XCTAssertEqual(wrong.envelope?.code, "invalid_credentials")
            XCTAssertEqual(unknown.envelope?.code, "invalid_credentials")
        }
    }

    func testMissingOrBogusTokenIsUnauthorized() async throws {
        try await withApp { harness in
            let missing = try await harness.send(.GET, "/v1/accounts")
            let bogus = try await harness.send(.GET, "/v1/accounts", token: "not-a-token")

            XCTAssertEqual(missing.status, .unauthorized)
            XCTAssertEqual(missing.envelope?.code, "unauthorized")
            XCTAssertEqual(bogus.status, .unauthorized)
        }
    }

    func testRefreshTokenCannotBeUsedAsAccessToken() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()

            let response = try await harness.send(.GET, "/v1/accounts", token: tokens.refreshToken)

            XCTAssertEqual(response.status, .unauthorized)
        }
    }

    func testAccessTokenExpiresAfter15Minutes() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()

            harness.advance(15 * 60 - 1)
            let before = try await harness.send(.GET, "/v1/accounts", token: tokens.accessToken)
            harness.advance(1)
            let after = try await harness.send(.GET, "/v1/accounts", token: tokens.accessToken)

            XCTAssertEqual(before.status, .ok)
            XCTAssertEqual(after.status, .unauthorized)
        }
    }

    func testRefreshRotatesTheRefreshToken() async throws {
        try await withApp { harness in
            let first = try await harness.login()

            let response = try await harness.send(
                .POST,
                "/v1/auth/refresh",
                json: RefreshRequest(refreshToken: first.refreshToken)
            )

            XCTAssertEqual(response.status, .ok)
            let second = try response.content.decode(SessionTokens.self)
            XCTAssertNotEqual(second.refreshToken, first.refreshToken)
            XCTAssertNotEqual(second.accessToken, first.accessToken)
            let accounts = try await harness.send(.GET, "/v1/accounts", token: second.accessToken)
            XCTAssertEqual(accounts.status, .ok)
        }
    }

    func testReusedRefreshTokenRevokesTheWholeSession() async throws {
        try await withApp { harness in
            let first = try await harness.login()
            let second = try await refresh(harness, first.refreshToken)
            // The real user keeps using the session normally...
            let third = try await refresh(harness, try XCTUnwrap(second).refreshToken)

            // ...then an attacker replays the first refresh token.
            let replay = try await harness.send(
                .POST,
                "/v1/auth/refresh",
                json: RefreshRequest(refreshToken: first.refreshToken)
            )

            XCTAssertEqual(replay.status, .unauthorized)
            XCTAssertEqual(replay.envelope?.code, "invalid_refresh_token")
            // Everything for that user is revoked, the real user's newest tokens included.
            let newest = try XCTUnwrap(third)
            let newRefresh = try await refresh(harness, newest.refreshToken)
            XCTAssertNil(newRefresh)
            let newAccess = try await harness.send(.GET, "/v1/accounts", token: newest.accessToken)
            XCTAssertEqual(newAccess.status, .unauthorized)
        }
    }

    func testRetryOfARefreshWhoseResponseWasLostGetsNewTokensWithinTheGraceWindow() async throws {
        try await withApp { harness in
            let first = try await harness.login()
            // The server rotates, but the response never reaches the app.
            let lost = try await refreshed(harness, first.refreshToken)

            harness.advance(10)
            let retried = try await refreshed(harness, first.refreshToken)

            XCTAssertNotEqual(retried.refreshToken, lost.refreshToken)
            let works = try await harness.send(.GET, "/v1/accounts", token: retried.accessToken)
            XCTAssertEqual(works.status, .ok)
            // The pair the app never received is revoked.
            let lostAccess = try await harness.send(.GET, "/v1/accounts", token: lost.accessToken)
            XCTAssertEqual(lostAccess.status, .unauthorized)
        }
    }

    func testGraceWindowEndsAfter30Seconds() async throws {
        try await withApp { harness in
            let first = try await harness.login()
            let second = try await refreshed(harness, first.refreshToken)

            harness.advance(31)
            let late = try await refresh(harness, first.refreshToken)

            XCTAssertNil(late)
            let revoked = try await harness.send(.GET, "/v1/accounts", token: second.accessToken)
            XCTAssertEqual(revoked.status, .unauthorized)
        }
    }

    func testGraceDoesNotApplyOnceTheNewPairHasBeenRefreshed() async throws {
        // If the new pair has been used to refresh, the old token can't be a lost response.
        try await withApp { harness in
            let first = try await harness.login()
            let second = try await refreshed(harness, first.refreshToken)
            _ = try await refreshed(harness, second.refreshToken)

            let replay = try await refresh(harness, first.refreshToken)

            XCTAssertNil(replay)
        }
    }

    /// Tokens, failing the test if the refresh is rejected.
    private func refreshed(_ harness: Harness, _ token: String) async throws -> SessionTokens {
        let tokens = try await refresh(harness, token)
        return try XCTUnwrap(tokens)
    }

    /// Tokens on 200, nil on 401.
    private func refresh(_ harness: Harness, _ token: String) async throws -> SessionTokens? {
        let response = try await harness.send(.POST, "/v1/auth/refresh", json: RefreshRequest(refreshToken: token))
        guard response.status == .ok else {
            XCTAssertEqual(response.status, .unauthorized)
            return nil
        }
        return try response.content.decode(SessionTokens.self)
    }

    func testExpiredRefreshTokenIsRejected() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()
            harness.advance(30 * 24 * 60 * 60)

            let response = try await harness.send(
                .POST,
                "/v1/auth/refresh",
                json: RefreshRequest(refreshToken: tokens.refreshToken)
            )

            XCTAssertEqual(response.status, .unauthorized)
        }
    }
}
