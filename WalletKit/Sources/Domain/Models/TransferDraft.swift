import Foundation

/// Everything needed to send a transfer, fixed when the user taps Send.
///
/// `id` is made by the app when the review screen opens, so a double tap or a retry after a
/// crash sends the same transfer. It is also the `Idempotency-Key` (SPEC section 5).
public struct TransferDraft: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let quote: FXQuote
    public let recipient: Recipient
    public let sourceAccountID: String

    public init(id: UUID, quote: FXQuote, recipient: Recipient, sourceAccountID: String) {
        self.id = id
        self.quote = quote
        self.recipient = recipient
        self.sourceAccountID = sourceAccountID
    }
}
