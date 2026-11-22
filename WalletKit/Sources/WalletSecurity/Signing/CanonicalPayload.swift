import Domain
import Foundation

/// The bytes a transfer approval signs (SPEC section 6): JSON with sorted keys and no
/// whitespace, amounts in minor units, the time in Unix milliseconds. The server checks the
/// signature over these exact bytes (sent alongside), then reads the fields back from them.
enum CanonicalPayload {
    static func encode(_ payload: ConfirmPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(
            Wire(
                transferId: payload.transferID.uuidString.lowercased(),
                amountMinor: payload.amountMinor,
                currency: payload.currency.code,
                recipientId: payload.recipientID,
                quoteId: payload.quoteID,
                nonce: payload.nonce,
                timestamp: Int64((payload.timestamp.timeIntervalSince1970 * 1000).rounded(.down))
            )
        )
    }

    /// Field names as `backend/openapi.yaml` has them.
    private struct Wire: Encodable {
        let transferId: String
        let amountMinor: Int64
        let currency: String
        let recipientId: String
        let quoteId: String
        let nonce: String
        let timestamp: Int64
    }
}
