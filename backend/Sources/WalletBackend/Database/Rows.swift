import Foundation

// One struct per table. Plain Sendable values decoded by SQLKit, so there are no Fluent
// `Model` classes and no unchecked Sendable conformances. Times are Unix milliseconds; money is
// integer minor units.

struct UserRow: Codable, Sendable {
    let id: String
    let email: String
    let passwordHash: String
}

struct AccountRow: Codable, Sendable {
    let id: String
    let userId: String
    let currency: String
    let balanceMinor: Int64
    let updatedAt: Int64
}

struct TransactionRow: Codable, Sendable {
    /// Monotonic, used as the pagination cursor.
    let seq: Int64
    let id: String
    let accountId: String
    let amountMinor: Int64
    let currency: String
    let description: String
    let createdAt: Int64
}

struct RecipientRow: Codable, Sendable {
    let id: String
    let userId: String
    let name: String
    let currency: String
    let accountLast4: String
}

struct TokenRow: Codable, Sendable {
    let tokenHash: String
    let userId: String
    /// "access" or "refresh".
    let kind: String
    let expiresAt: Int64
    /// 1 once a refresh token has been exchanged. Reusing it revokes the whole session family.
    let revoked: Int
    /// Shared by the access and refresh token issued together, so a pair can be revoked as one.
    let pairId: String
    /// When this refresh token was exchanged, and the hash of the refresh token that
    /// replaced it. Used for the lost-response grace window (ADR-016).
    var rotatedAt: Int64?
    var replacedBy: String?
}

struct QuoteRow: Codable, Sendable {
    let id: String
    let userId: String
    let sourceMinor: Int64
    let sourceCurrency: String
    let targetMinor: Int64
    let targetCurrency: String
    let feeMinor: Int64
    /// Decimal string, never a float.
    let rate: String
    let expiresAt: Int64
}

struct TransferRow: Codable, Sendable {
    let id: String
    let userId: String
    let quoteId: String
    let recipientId: String
    let sourceAccountId: String
    let sourceMinor: Int64
    let sourceCurrency: String
    let targetMinor: Int64
    let targetCurrency: String
    let feeMinor: Int64
    let status: String
    let failureReason: String?
    let createdAt: Int64
    let updatedAt: Int64
}

struct IdempotencyRow: Codable, Sendable {
    /// "<userId>:<Idempotency-Key>", so keys from different users never collide.
    let scopedKey: String
    let method: String
    let path: String
    /// SHA-256 of the request body. Same key + different body is rejected.
    let bodyHash: String
    /// Random per request: tells the request holding the lock apart from a concurrent one.
    let lockOwner: String
    /// 0 while the first request is still running.
    let completed: Int
    let status: Int
    let responseBody: Data
    let createdAt: Int64
}
