import Foundation

/// What the send-money screens read before a transfer exists: saved recipients and quotes.
/// `RemoteTransfersRepository` in Networking implements it (ADR-004).
public protocol TransfersRepository: Sendable {
    func recipients() async throws(TransferError) -> [Recipient]

    /// A price for sending `sourceAmount` to `targetCurrency`, valid until `expiresAt` (30 s).
    func quote(sourceAmount: Money, targetCurrency: Currency) async throws(TransferError) -> FXQuote

    /// A nonce for the user to sign, for the transfer the app is about to create with `transferID`.
    func challenge(transferID: UUID) async throws(TransferError) -> SigningChallenge
}
