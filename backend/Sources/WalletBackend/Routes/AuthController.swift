import SQLKit
import Vapor

/// Sandbox login and refresh. Device binding and the binding token come in Phase 7.
struct AuthController: Sendable {
    let clock: BackendClock
    /// Verified against when the email is unknown, so a missing account takes as long
    /// as a wrong password and response time doesn't reveal which emails exist.
    let dummyHash: String

    @Sendable func login(_ request: Request) async throws -> SessionTokens {
        let body = try request.content.decode(LoginRequest.self)
        let email = body.email.trimmingCharacters(in: .whitespaces).lowercased()
        let user = try await request.sql.select().column("*").from("users")
            .where("email", .equal, email)
            .first(decoding: UserRow.self)
        // The async hasher runs bcrypt on the thread pool, not the concurrency pool, so slow
        // hashing can't starve other requests.
        let passwordMatches = try await request.password.async
            .verify(body.password, created: user?.passwordHash ?? dummyHash).get()
        guard let user, passwordMatches else { throw APIFailure.invalidCredentials }
        return try await issueTokens(userID: user.id, sql: request.sql)
    }

    /// Refresh tokens rotate: each one works once. Presenting a used one means it was
    /// copied, so every token for that user is revoked and they must sign in again.
    /// The one exception is a retry of a refresh whose response was lost (`retryWithinGrace`).
    @Sendable func refresh(_ request: Request) async throws -> SessionTokens {
        let body = try request.content.decode(RefreshRequest.self)
        let hash = Tokens.hash(body.refreshToken)
        let now = clock.nowMillis

        // The transaction returns nil instead of throwing on a bad token: throwing would
        // roll back the reuse revocation, which must stick.
        let tokens: SessionTokens? = try await request.db.transaction { database in
            let sql = try database.sqlDatabase()
            // Claim the token atomically: only one of two concurrent refreshes gets a row back.
            let claimed = try await sql.update("tokens")
                .set("revoked", to: 1)
                .set("rotatedAt", to: now)
                .where("tokenHash", .equal, hash)
                .where("kind", .equal, "refresh")
                .where("revoked", .equal, 0)
                .where("expiresAt", .greaterThan, now)
                .returning("*")
                .first(decoding: TokenRow.self)
            if let claimed {
                return try await rotate(claimed, sql: sql)
            }
            guard
                let used = try await sql.select().column("*").from("tokens")
                    .where("tokenHash", .equal, hash)
                    .where("kind", .equal, "refresh")
                    .where("revoked", .equal, 1)
                    .first(decoding: TokenRow.self)
            else { return nil }
            if let retried = try await retryWithinGrace(used, now: now, sql: sql) {
                return retried
            }
            try await sql.update("tokens").set("revoked", to: 1).where("userId", .equal, used.userId).run()
            return nil
        }
        guard let tokens else { throw APIFailure.invalidRefreshToken }
        return tokens
    }

    /// Issues a new pair and records which refresh token replaced `old`.
    private func rotate(_ old: TokenRow, sql: any SQLDatabase) async throws -> SessionTokens {
        let issued = try await issueTokens(userID: old.userId, sql: sql)
        try await sql.update("tokens")
            .set("replacedBy", to: Tokens.hash(issued.refreshToken))
            .where("tokenHash", .equal, old.tokenHash)
            .run()
        return issued
    }

    /// A used refresh token presented again within 30 s of its rotation, while the pair it
    /// was rotated into has never been refreshed, is a client retrying after a lost response,
    /// not theft. The unused pair is revoked and a fresh one issued. If the thief got there
    /// first, the real user's next refresh with the revoked pair is reuse and revokes everything.
    private func retryWithinGrace(_ used: TokenRow, now: Int64, sql: any SQLDatabase) async throws -> SessionTokens? {
        guard let rotatedAt = used.rotatedAt, now - rotatedAt <= Tokens.refreshGraceMillis,
            let replacement = used.replacedBy
        else { return nil }
        guard
            let unused = try await sql.update("tokens")
                .set("revoked", to: 1)
                .where("tokenHash", .equal, replacement)
                .where("revoked", .equal, 0)
                .returning("*")
                .first(decoding: TokenRow.self)
        else { return nil }
        try await sql.update("tokens").set("revoked", to: 1).where("pairId", .equal, unused.pairId).run()
        return try await rotate(used, sql: sql)
    }

    private func issueTokens(userID: String, sql: any SQLDatabase) async throws -> SessionTokens {
        let now = clock.nowMillis
        let access = Tokens.generate()
        let refresh = Tokens.generate()
        let pairID = UUID().uuidString
        try await sql.insert(into: "tokens").models([
            TokenRow(
                tokenHash: Tokens.hash(access),
                userId: userID,
                kind: "access",
                expiresAt: now + Tokens.accessLifetimeSeconds * 1000,
                revoked: 0,
                pairId: pairID
            ),
            TokenRow(
                tokenHash: Tokens.hash(refresh),
                userId: userID,
                kind: "refresh",
                expiresAt: now + Tokens.refreshLifetimeSeconds * 1000,
                revoked: 0,
                pairId: pairID
            ),
        ]).run()
        return SessionTokens(accessToken: access, refreshToken: refresh, expiresIn: Tokens.accessLifetimeSeconds)
    }
}
