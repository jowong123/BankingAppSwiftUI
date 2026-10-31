import SQLKit
import Vapor

/// Opaque bearer tokens. Only their SHA-256 hashes are stored, so a leaked database
/// can't be replayed as live sessions.
enum Tokens {
    static let accessLifetimeSeconds: Int64 = 15 * 60
    static let refreshLifetimeSeconds: Int64 = 30 * 24 * 60 * 60
    /// How long after a rotation the old refresh token may be presented again, as a retry
    /// of a response that never arrived, without counting as reuse.
    static let refreshGraceMillis: Int64 = 30_000

    /// 32 random bytes, base64url without padding.
    static func generate() -> String {
        Data([UInt8].random(count: 32)).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).hex
    }
}

extension Request {
    var sql: any SQLDatabase {
        get throws {
            guard let sql = db as? any SQLDatabase else {
                throw Abort(.internalServerError, reason: "Database is not SQL")
            }
            return sql
        }
    }
}
