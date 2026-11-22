import Foundation

/// Everything needed to send a transfer, fixed when the user taps Send.
///
/// `id` is made by the app when the review screen opens, so a double tap or a retry after a
/// crash sends the same transfer. It is also the `Idempotency-Key` (SPEC section 5).
///
/// `confirmation` is the user's Face ID approval, signed before the draft reaches the
/// outbox, so the outbox never needs to show a prompt (ADR-023).
public struct TransferDraft: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let quote: FXQuote
    public let recipient: Recipient
    public let sourceAccountID: String
    public let confirmation: SignedConfirmation

    public init(
        id: UUID,
        quote: FXQuote,
        recipient: Recipient,
        sourceAccountID: String,
        confirmation: SignedConfirmation
    ) {
        self.id = id
        self.quote = quote
        self.recipient = recipient
        self.sourceAccountID = sourceAccountID
        self.confirmation = confirmation
    }
}
