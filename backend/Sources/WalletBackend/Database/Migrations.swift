import Fluent
import SQLKit
import Vapor

/// Creates every table. Fluent runs and records migrations; the DDL is SQLKit.
struct CreateSchema: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let sql = try database.sqlDatabase()
        try await createIdentityTables(sql)
        try await createAccountTables(sql)
        try await createTransferTables(sql)
    }

    /// Users and their session tokens.
    private func createIdentityTables(_ sql: any SQLDatabase) async throws {
        try await sql.create(table: "users")
            .column("id", type: .text, .primaryKey(autoIncrement: false))
            .column("email", type: .text, .notNull, .unique)
            .column("passwordHash", type: .text, .notNull)
            .run()

        try await sql.create(table: "tokens")
            .column("tokenHash", type: .text, .primaryKey(autoIncrement: false))
            .column("userId", type: .text, .notNull)
            .column("kind", type: .text, .notNull)
            .column("expiresAt", type: .bigint, .notNull)
            .column("revoked", type: .int, .notNull)
            .column("pairId", type: .text, .notNull)
            .column("rotatedAt", type: .bigint)
            .column("replacedBy", type: .text)
            .run()
    }

    /// Balances, history and saved payees.
    private func createAccountTables(_ sql: any SQLDatabase) async throws {
        try await sql.create(table: "accounts")
            .column("id", type: .text, .primaryKey(autoIncrement: false))
            .column("userId", type: .text, .notNull)
            .column("currency", type: .text, .notNull)
            .column("balanceMinor", type: .bigint, .notNull)
            .column("updatedAt", type: .bigint, .notNull)
            .run()

        try await sql.create(table: "transactions")
            .column("seq", type: .bigint, .primaryKey(autoIncrement: false))
            .column("id", type: .text, .notNull, .unique)
            .column("accountId", type: .text, .notNull)
            .column("amountMinor", type: .bigint, .notNull)
            .column("currency", type: .text, .notNull)
            .column("description", type: .text, .notNull)
            .column("createdAt", type: .bigint, .notNull)
            .run()

        try await sql.create(table: "recipients")
            .column("id", type: .text, .primaryKey(autoIncrement: false))
            .column("userId", type: .text, .notNull)
            .column("name", type: .text, .notNull)
            .column("currency", type: .text, .notNull)
            .column("accountLast4", type: .text, .notNull)
            .run()
    }

    /// Quotes, transfers and the idempotency store.
    private func createTransferTables(_ sql: any SQLDatabase) async throws {
        try await sql.create(table: "quotes")
            .column("id", type: .text, .primaryKey(autoIncrement: false))
            .column("userId", type: .text, .notNull)
            .column("sourceMinor", type: .bigint, .notNull)
            .column("sourceCurrency", type: .text, .notNull)
            .column("targetMinor", type: .bigint, .notNull)
            .column("targetCurrency", type: .text, .notNull)
            .column("feeMinor", type: .bigint, .notNull)
            .column("rate", type: .text, .notNull)
            .column("expiresAt", type: .bigint, .notNull)
            .run()

        // quoteId is unique: one quote can pay for one transfer only.
        try await sql.create(table: "transfers")
            .column("id", type: .text, .primaryKey(autoIncrement: false))
            .column("userId", type: .text, .notNull)
            .column("quoteId", type: .text, .notNull, .unique)
            .column("recipientId", type: .text, .notNull)
            .column("sourceAccountId", type: .text, .notNull)
            .column("sourceMinor", type: .bigint, .notNull)
            .column("sourceCurrency", type: .text, .notNull)
            .column("targetMinor", type: .bigint, .notNull)
            .column("targetCurrency", type: .text, .notNull)
            .column("feeMinor", type: .bigint, .notNull)
            .column("status", type: .text, .notNull)
            .column("failureReason", type: .text)
            .column("createdAt", type: .bigint, .notNull)
            .column("updatedAt", type: .bigint, .notNull)
            .run()

        try await sql.create(table: "idempotency")
            .column("scopedKey", type: .text, .primaryKey(autoIncrement: false))
            .column("method", type: .text, .notNull)
            .column("path", type: .text, .notNull)
            .column("bodyHash", type: .text, .notNull)
            .column("lockOwner", type: .text, .notNull)
            .column("completed", type: .int, .notNull)
            .column("status", type: .int, .notNull)
            .column("responseBody", type: .blob, .notNull)
            .column("createdAt", type: .bigint, .notNull)
            .run()
    }

    func revert(on database: any Database) async throws {
        let sql = try database.sqlDatabase()
        for table in [
            "idempotency", "transfers", "quotes", "tokens", "recipients", "transactions", "accounts", "users",
        ] {
            try await sql.drop(table: table).ifExists().run()
        }
    }
}

extension Database {
    func sqlDatabase() throws -> any SQLDatabase {
        guard let sql = self as? any SQLDatabase else {
            throw Abort(.internalServerError, reason: "Database is not SQL")
        }
        return sql
    }
}
