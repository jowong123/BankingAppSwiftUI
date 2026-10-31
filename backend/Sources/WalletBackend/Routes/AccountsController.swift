import SQLKit
import Vapor

struct AccountsController: Sendable {
    static let defaultPageSize = 20
    static let maxPageSize = 100

    @Sendable func list(_ request: Request) async throws -> AccountsResponse {
        let user = try request.auth.require(AuthenticatedUser.self)
        let rows = try await request.sql.select().column("*").from("accounts")
            .where("userId", .equal, user.id)
            .orderBy("id")
            .all(decoding: AccountRow.self)
        return AccountsResponse(accounts: rows.map(AccountDTO.init))
    }

    /// Newest first. The cursor is the opaque position after the last item returned;
    /// keyset pagination, so new transactions don't shift pages like OFFSET would.
    @Sendable func transactions(_ request: Request) async throws -> TransactionPage {
        let user = try request.auth.require(AuthenticatedUser.self)
        let accountID = try request.parameters.require("accountID")
        let limit = try request.query.get(Int?.self, at: "limit") ?? Self.defaultPageSize
        guard (1...Self.maxPageSize).contains(limit) else {
            throw APIFailure.badRequest("limit must be 1...\(Self.maxPageSize).")
        }
        let cursor = try (request.query.get(String?.self, at: "cursor")).map(Self.decodeCursor)

        // 404, not 403, for another user's account: don't confirm that it exists.
        let account = try await request.sql.select().column("id").from("accounts")
            .where("id", .equal, accountID)
            .where("userId", .equal, user.id)
            .first()
        guard account != nil else { throw APIFailure.notFound }

        var query = try request.sql.select().column("*").from("transactions")
            .where("accountId", .equal, accountID)
        if let cursor {
            query = query.where("seq", .lessThan, cursor)
        }
        let rows = try await query.orderBy("seq", .descending).limit(limit + 1).all(decoding: TransactionRow.self)

        let page = Array(rows.prefix(limit))
        let nextCursor = rows.count > limit ? page.last.map { Self.encodeCursor($0.seq) } : nil
        return TransactionPage(items: page.map(TransactionDTO.init), nextCursor: nextCursor)
    }

    static func encodeCursor(_ seq: Int64) -> String {
        Data("seq:\(seq)".utf8).base64EncodedString()
    }

    static func decodeCursor(_ cursor: String) throws -> Int64 {
        guard let data = Data(base64Encoded: cursor),
            let text = String(data: data, encoding: .utf8),
            text.hasPrefix("seq:"),
            let seq = Int64(text.dropFirst(4))
        else {
            throw APIFailure.badRequest("cursor is invalid.")
        }
        return seq
    }
}

struct RecipientsController: Sendable {
    @Sendable func list(_ request: Request) async throws -> RecipientsResponse {
        let user = try request.auth.require(AuthenticatedUser.self)
        let rows = try await request.sql.select().column("*").from("recipients")
            .where("userId", .equal, user.id)
            .orderBy("name")
            .all(decoding: RecipientRow.self)
        return RecipientsResponse(recipients: rows.map(RecipientDTO.init))
    }
}
