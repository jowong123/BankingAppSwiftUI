import Fluent
import SQLKit
import Vapor

/// Fake sandbox data. The credentials are public demo values, not secrets: the README
/// lists them so reviewers can sign in. Only their bcrypt hashes are stored.
enum Sandbox {
    static let demoEmail = "demo@wallet.test"
    static let demoPassword = "sandbox-demo"
    /// A second user, so tests can prove one user can't read another's data.
    static let otherEmail = "other@wallet.test"
    static let otherPassword = "sandbox-other"
}

struct SeedSandboxData: AsyncMigration {
    let bcryptCost: Int
    let clock: BackendClock

    func prepare(on database: any Database) async throws {
        let sql = try database.sqlDatabase()
        let now = clock.nowMillis

        let users = [
            UserRow(
                id: "usr_demo",
                email: Sandbox.demoEmail,
                passwordHash: try Bcrypt.hash(Sandbox.demoPassword, cost: bcryptCost)
            ),
            UserRow(
                id: "usr_other",
                email: Sandbox.otherEmail,
                passwordHash: try Bcrypt.hash(Sandbox.otherPassword, cost: bcryptCost)
            ),
        ]
        try await sql.insert(into: "users").models(users).run()

        let accounts = [
            AccountRow(id: "acc_sgd", userId: "usr_demo", currency: "SGD", balanceMinor: 1_250_000, updatedAt: now),
            AccountRow(id: "acc_usd", userId: "usr_demo", currency: "USD", balanceMinor: 320_000, updatedAt: now),
            AccountRow(id: "acc_jpy", userId: "usr_demo", currency: "JPY", balanceMinor: 150_000, updatedAt: now),
            AccountRow(id: "acc_kwd", userId: "usr_demo", currency: "KWD", balanceMinor: 120_500, updatedAt: now),
            AccountRow(id: "acc_other_sgd", userId: "usr_other", currency: "SGD", balanceMinor: 50_000, updatedAt: now),
        ]
        try await sql.insert(into: "accounts").models(accounts).run()

        try await sql.insert(into: "transactions").models(Self.transactions(now: now)).run()

        let recipients = [
            RecipientRow(
                id: "rcp_alice_usd", userId: "usr_demo", name: "Alice Tan", currency: "USD", accountLast4: "4821"),
            RecipientRow(
                id: "rcp_kenji_jpy", userId: "usr_demo", name: "Kenji Sato", currency: "JPY", accountLast4: "0937"),
            RecipientRow(
                id: "rcp_marie_eur", userId: "usr_demo", name: "Marie Dubois", currency: "EUR", accountLast4: "7710"),
            RecipientRow(
                id: "rcp_omar_kwd", userId: "usr_demo", name: "Omar Al-Sabah", currency: "KWD", accountLast4: "3302"),
            RecipientRow(
                id: "rcp_other_usd", userId: "usr_other", name: "Bob Lee", currency: "USD", accountLast4: "1111"),
        ]
        try await sql.insert(into: "recipients").models(recipients).run()
    }

    func revert(on database: any Database) async throws {
        let sql = try database.sqlDatabase()
        for table in ["recipients", "transactions", "accounts", "users"] {
            try await sql.delete(from: table).run()
        }
    }

    /// 45 SGD transactions (enough for three pages of 20) and a few in other currencies,
    /// one hour apart going back from `now`.
    static func transactions(now: Int64) -> [TransactionRow] {
        let hour: Int64 = 3_600_000
        let merchants = ["Kopi Corner", "MRT Top-up", "FairPrice", "Grab", "Salary", "Netflix", "Uniqlo", "Refund"]
        var rows: [TransactionRow] = []
        var seq: Int64 = 1
        for index in 0..<45 {
            let merchant = merchants[index % merchants.count]
            let incoming = merchant == "Salary" || merchant == "Refund"
            let amount = Int64(350 + (index * 137) % 9_000)
            rows.append(
                TransactionRow(
                    seq: seq,
                    id: "txn_sgd_\(index)",
                    accountId: "acc_sgd",
                    amountMinor: incoming ? amount * 10 : -amount,
                    currency: "SGD",
                    description: merchant,
                    createdAt: now - Int64(45 - index) * hour
                )
            )
            seq += 1
        }
        let others = [
            SeedTransaction(account: "acc_usd", currency: "USD", amountMinor: -4_599, description: "Amazon"),
            SeedTransaction(account: "acc_usd", currency: "USD", amountMinor: 120_000, description: "Transfer in"),
            SeedTransaction(account: "acc_jpy", currency: "JPY", amountMinor: -1_200, description: "Lawson"),
            SeedTransaction(account: "acc_jpy", currency: "JPY", amountMinor: 50_000, description: "Transfer in"),
            SeedTransaction(account: "acc_kwd", currency: "KWD", amountMinor: -2_750, description: "Talabat"),
            SeedTransaction(account: "acc_other_sgd", currency: "SGD", amountMinor: -900, description: "Kopi Corner"),
        ]
        for (index, other) in others.enumerated() {
            rows.append(
                TransactionRow(
                    seq: seq,
                    id: "txn_\(other.account)_\(index)",
                    accountId: other.account,
                    amountMinor: other.amountMinor,
                    currency: other.currency,
                    description: other.description,
                    createdAt: now - Int64(others.count - index) * hour
                )
            )
            seq += 1
        }
        return rows
    }
}

private struct SeedTransaction {
    let account: String
    let currency: String
    let amountMinor: Int64
    let description: String
}
