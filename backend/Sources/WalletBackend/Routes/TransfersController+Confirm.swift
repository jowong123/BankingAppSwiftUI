import FluentKit
import SQLKit
import Vapor

/// Confirm and settlement. Phase 6 confirms without a signature; Phase 7 makes the signed
/// payload mandatory on this same route (ADR-022).
///
/// Every change is a conditional update that says what it expects to find (`WHERE status =`,
/// `WHERE balanceMinor >=`) and reports whether it changed a row. Two requests racing for the
/// same transfer or account can't both win, on SQLite or on a database with weaker isolation.
extension TransfersController {
    /// Moves the money: claims the transfer (`awaiting_confirmation` → `processing`), debits
    /// the account if it still covers the amount, and adds the history row, in one database
    /// transaction. `sourceMinor` includes the fee: the user is debited exactly that.
    ///
    /// - Safe to repeat: only an unconfirmed transfer changes; any other status is returned
    ///   as it is.
    /// - Too late (more than `confirmGraceMillis` after the quote expired) fails it with
    ///   `quote_expired` and debits nothing, so an old rate can't be kept as a free option.
    /// - Not enough balance fails it with `insufficient_funds` and debits nothing.
    @Sendable func confirm(_ request: Request) async throws -> TransferDTO {
        let user = try request.auth.require(AuthenticatedUser.self)
        let id = try request.parameters.require("transferID").lowercased()
        let now = clock.nowMillis
        let row = try await request.db.transaction { database in
            let sql = try database.sqlDatabase()
            guard let row = try await Self.transfer(id, userID: user.id, sql: sql) else {
                throw APIFailure.notFound
            }
            guard row.status == "awaiting_confirmation" else {
                return row
            }
            let quote = try await sql.select().column("*").from("quotes")
                .where("id", .equal, row.quoteId)
                .first(decoding: QuoteRow.self)
            guard let quote, now <= quote.expiresAt + Self.confirmGraceMillis else {
                return try await Self.move(
                    row, StatusChange(from: "awaiting_confirmation", next: "failed", reason: "quote_expired"), now: now,
                    sql: sql)
            }
            guard
                let claimed = try await Self.update(
                    row, StatusChange(from: "awaiting_confirmation", next: "processing", reason: nil), now: now,
                    sql: sql)
            else {
                // Another confirm got there first.
                return try await Self.transfer(id, userID: user.id, sql: sql) ?? row
            }
            guard
                let account = try await Self.changeBalance(
                    of: row.sourceAccountId, by: -row.sourceMinor, now: now, sql: sql)
            else {
                return try await Self.move(
                    claimed, StatusChange(from: "processing", next: "failed", reason: "insufficient_funds"), now: now,
                    sql: sql)
            }
            let recipient = try await sql.select().column("name").from("recipients")
                .where("id", .equal, row.recipientId)
                .first(decoding: NameRow.self)
            try await Self.addHistory(
                -row.sourceMinor,
                to: account,
                id: "txn_\(row.id)",
                description: "To \(recipient?.name ?? "recipient")",
                sql: sql
            )
            return claimed
        }
        return TransferDTO(row)
    }

    /// Settles a `processing` transfer once `settleMillis` have passed since the confirm.
    /// Called when the transfer is read, so the sandbox needs no background job and tests
    /// control it with the clock. The `declinedRecipientID` payee is declined and refunded,
    /// to show the Processing → Failed path.
    func settleIfDue(_ row: TransferRow, on database: any Database) async throws -> TransferRow {
        let now = clock.nowMillis
        guard row.status == "processing", now - row.updatedAt >= Self.settleMillis else {
            return row
        }
        return try await database.transaction { database in
            let sql = try database.sqlDatabase()
            let declined = row.recipientId == Sandbox.declinedRecipientID
            // Only the read that moves it out of `processing` settles it (and refunds once).
            guard
                let settled = try await Self.update(
                    row,
                    StatusChange(
                        from: "processing", next: declined ? "failed" : "completed", reason: declined ? "declined" : nil
                    ),
                    now: now, sql: sql)
            else {
                return try await Self.transfer(row.id, userID: row.userId, sql: sql) ?? row
            }
            if declined,
                let account = try await Self.changeBalance(
                    of: row.sourceAccountId, by: row.sourceMinor, now: now, sql: sql)
            {
                try await Self.addHistory(
                    row.sourceMinor,
                    to: account,
                    id: "txn_\(row.id)_refund",
                    description: "Refund: transfer declined",
                    sql: sql
                )
            }
            return settled
        }
    }

    /// How long a confirmed transfer stays `processing` in the sandbox.
    static let settleMillis: Int64 = 3_000
    /// How long after its quote expires a created transfer can still be confirmed: room for
    /// the app's retries, not for waiting to see where the rate goes.
    static let confirmGraceMillis: Int64 = 120_000

    static func transfer(_ id: String, userID: String, sql: any SQLDatabase) async throws -> TransferRow? {
        try await sql.select().column("*").from("transfers")
            .where("id", .equal, id).where("userId", .equal, userID)
            .first(decoding: TransferRow.self)
    }

    /// Changes the status only if it is still `change.from`. `nil` if another request changed it.
    private static func update(
        _ row: TransferRow,
        _ change: StatusChange,
        now: Int64,
        sql: any SQLDatabase
    ) async throws -> TransferRow? {
        try await sql.update("transfers")
            .set("status", to: change.next)
            .set("failureReason", to: change.reason)
            .set("updatedAt", to: now)
            .where("id", .equal, row.id)
            .where("status", .equal, change.from)
            .returning("*")
            .first(decoding: TransferRow.self)
    }

    /// `update`, then the row as it is now whichever request won.
    private static func move(
        _ row: TransferRow,
        _ change: StatusChange,
        now: Int64,
        sql: any SQLDatabase
    ) async throws -> TransferRow {
        if let moved = try await update(row, change, now: now, sql: sql) {
            return moved
        }
        return try await transfer(row.id, userID: row.userId, sql: sql) ?? row
    }

    /// Adds `amountMinor` to the balance in the database itself (`balanceMinor = balanceMinor
    /// + ?`), never from a value read earlier. A debit only happens if the balance covers it.
    /// `nil` if it didn't (or the account is gone).
    private static func changeBalance(
        of accountID: String,
        by amountMinor: Int64,
        now: Int64,
        sql: any SQLDatabase
    ) async throws -> AccountRow? {
        var update = sql.update("accounts")
            .set(
                SQLIdentifier("balanceMinor"),
                to: SQLBinaryExpression(SQLIdentifier("balanceMinor"), .add, SQLBind(amountMinor))
            )
            .set("updatedAt", to: now)
            .where("id", .equal, accountID)
        if amountMinor < 0 {
            update = update.where("balanceMinor", .greaterThanOrEqual, -amountMinor)
        }
        return try await update.returning("*").first(decoding: AccountRow.self)
    }

    /// The history row for a balance change, inside the same transaction. Its unique id
    /// (`txn_<transfer id>`) is a backstop: a second debit or refund for the same transfer
    /// fails the insert and rolls the whole transaction back.
    private static func addHistory(
        _ amountMinor: Int64,
        to account: AccountRow,
        id: String,
        description: String,
        sql: any SQLDatabase
    ) async throws {
        let last = try await sql.select().column("seq").from("transactions")
            .orderBy("seq", .descending).limit(1)
            .first(decoding: SeqRow.self)
        try await sql.insert(into: "transactions").model(
            TransactionRow(
                seq: (last?.seq ?? 0) + 1,
                id: id,
                accountId: account.id,
                amountMinor: amountMinor,
                currency: account.currency,
                description: description,
                createdAt: account.updatedAt
            )
        ).run()
    }
}

/// A status move that only happens if the transfer is still in `from`.
private struct StatusChange {
    let from: String
    let next: String
    let reason: String?
}

private struct NameRow: Decodable {
    let name: String
}

private struct SeqRow: Decodable {
    let seq: Int64
}
