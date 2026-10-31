import SQLKit
import Vapor

struct AuthenticatedUser: Authenticatable {
    let id: String
}

/// Looks the bearer token up by its hash and logs the user in if it's an unexpired
/// access token. Anything else leaves the request unauthenticated, and the guard
/// middleware after this returns 401 `unauthorized`.
struct TokenAuthenticator: AsyncBearerAuthenticator {
    let clock: BackendClock

    func authenticate(bearer: BearerAuthorization, for request: Request) async throws {
        let row = try await request.sql.select().column("*").from("tokens")
            .where("tokenHash", .equal, Tokens.hash(bearer.token))
            .where("kind", .equal, "access")
            .first(decoding: TokenRow.self)
        guard let row, row.revoked == 0, row.expiresAt > clock.nowMillis else { return }
        request.auth.login(AuthenticatedUser(id: row.userId))
    }
}
