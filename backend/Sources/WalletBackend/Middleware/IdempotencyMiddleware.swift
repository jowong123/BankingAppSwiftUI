import SQLKit
import Vapor

/// Makes POSTs safe to retry (SPEC section 7: same `Idempotency-Key` returns the original
/// response). Runs after authentication, so keys are scoped per user.
///
/// 1. Expired records (older than 24 h) are deleted.
/// 2. The key is **claimed** with an insert that ignores conflicts, then read back. If
///    another request owns it and hasn't finished, this one gets 409 instead of running
///    the handler a second time. That closes the race where two retries arrive together.
/// 3. A finished record with the same method, path and body hash is replayed verbatim with
///    `Idempotent-Replayed: true`. Anything else with that key is 422 `idempotency_mismatch`.
/// 4. After the handler runs, a returned response below 500 is stored. A thrown error
///    (every `APIFailure`) or a 5xx releases the key so a retry runs the handler again.
///    That's safe because handlers write in one transaction: a failed request changed nothing.
struct IdempotencyMiddleware: AsyncMiddleware {
    static let header = "Idempotency-Key"
    static let replayedHeader = "Idempotent-Replayed"
    static let lifetimeMillis: Int64 = 24 * 60 * 60 * 1000
    /// An unfinished claim older than this belongs to a request that crashed or hung; a
    /// retry may take it over. Handlers are idempotent on their own IDs, so that's safe.
    static let lockLeaseMillis: Int64 = 60_000
    static let maxBodyBytes = 64 * 1024

    let required: Bool
    let clock: BackendClock

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard request.method == .POST else { return try await next.respond(to: request) }
        guard let key = request.headers.first(name: Self.header) else {
            if required { throw APIFailure.idempotencyKeyRequired }
            return try await next.respond(to: request)
        }
        guard (1...255).contains(key.count) else {
            throw APIFailure.badRequest("\(Self.header) must be 1...255 characters.")
        }
        let sql = try request.sql
        let claim = try await makeClaim(key: key, for: request)

        // A record is gone at exactly 24 h, like a quote at exactly 30 s. An unfinished
        // claim is gone once its lease runs out.
        try await sql.delete(from: "idempotency")
            .where("createdAt", .lessThanOrEqual, claim.createdAt - Self.lifetimeMillis).run()
        try await sql.delete(from: "idempotency")
            .where("completed", .equal, 0)
            .where("createdAt", .lessThanOrEqual, claim.createdAt - Self.lockLeaseMillis).run()
        try await sql.insert(into: "idempotency").model(claim).ignoringConflicts(with: "scopedKey").run()
        guard
            let stored = try await sql.select().column("*").from("idempotency")
                .where("scopedKey", .equal, claim.scopedKey)
                .first(decoding: IdempotencyRow.self)
        else {
            throw Abort(.internalServerError, reason: "Idempotency record missing")
        }

        guard stored.lockOwner == claim.lockOwner else {
            return try replay(stored, for: claim)
        }

        let response: Response
        do {
            response = try await next.respond(to: request)
        } catch {
            try await release(claim, sql: sql)
            throw error
        }
        try await complete(claim, with: response, sql: sql)
        return response
    }

    private func makeClaim(key: String, for request: Request) async throws -> IdempotencyRow {
        let user = try request.auth.require(AuthenticatedUser.self)
        let body = try await request.body.collect(max: Self.maxBodyBytes).get()
        return IdempotencyRow(
            scopedKey: "\(user.id):\(key)",
            method: request.method.rawValue,
            path: request.url.path,
            bodyHash: SHA256.hash(data: body.map { Data(buffer: $0) } ?? Data()).hex,
            lockOwner: UUID().uuidString,
            completed: 0,
            status: 0,
            responseBody: Data(),
            createdAt: clock.nowMillis
        )
    }

    /// Stores a response below 500 for replay; releases the key for anything else.
    private func complete(_ claim: IdempotencyRow, with response: Response, sql: any SQLDatabase) async throws {
        guard response.status.code < 500, let responseBody = response.body.data else {
            try await release(claim, sql: sql)
            return
        }
        try await sql.update("idempotency")
            .set("completed", to: 1)
            .set("status", to: Int(response.status.code))
            .set("responseBody", to: responseBody)
            .where("scopedKey", .equal, claim.scopedKey)
            .where("lockOwner", .equal, claim.lockOwner)
            .run()
    }

    private func replay(_ stored: IdempotencyRow, for claim: IdempotencyRow) throws -> Response {
        guard stored.method == claim.method, stored.path == claim.path, stored.bodyHash == claim.bodyHash else {
            throw APIFailure.idempotencyMismatch
        }
        guard stored.completed == 1 else { throw APIFailure.idempotencyInProgress }
        var headers = HTTPHeaders()
        headers.contentType = .json
        headers.add(name: Self.replayedHeader, value: "true")
        return Response(
            status: HTTPResponseStatus(statusCode: stored.status),
            headers: headers,
            body: .init(data: stored.responseBody)
        )
    }

    private func release(_ claim: IdempotencyRow, sql: any SQLDatabase) async throws {
        try await sql.delete(from: "idempotency")
            .where("scopedKey", .equal, claim.scopedKey)
            .where("lockOwner", .equal, claim.lockOwner)
            .run()
    }
}
