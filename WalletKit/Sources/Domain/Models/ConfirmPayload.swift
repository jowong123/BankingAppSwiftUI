import Foundation

/// What the user approves with Face ID before a transfer moves money (SPEC section 6). Every
/// field is known when Send is tapped, before the transfer is created. The server checks each
/// one against the stored transfer and the nonce it issued.
public struct ConfirmPayload: Hashable, Sendable {
    public let transferID: UUID
    /// The amount debited, fee included, in the source currency's minor units.
    public let amountMinor: Int64
    public let currency: Currency
    public let recipientID: String
    public let quoteID: String
    /// From `POST /v1/transfers/{id}/challenge`: single use, valid 60 s.
    public let nonce: String
    public let timestamp: Date

    public init(
        transferID: UUID,
        amountMinor: Int64,
        currency: Currency,
        recipientID: String,
        quoteID: String,
        nonce: String,
        timestamp: Date
    ) {
        self.transferID = transferID
        self.amountMinor = amountMinor
        self.currency = currency
        self.recipientID = recipientID
        self.quoteID = quoteID
        self.nonce = nonce
        self.timestamp = timestamp
    }
}

/// A signed approval, kept in the outbox and sent unchanged on every retry of the confirm.
public struct SignedConfirmation: Hashable, Sendable {
    /// The exact bytes that were signed: canonical JSON of a `ConfirmPayload`.
    public let payload: Data
    /// DER ECDSA P-256 signature over SHA-256 of `payload`, by the Secure Enclave key.
    public let signature: Data
    /// App Attest assertion over `payload`; `nil` where App Attest isn't available.
    public let assertion: Data?

    public init(payload: Data, signature: Data, assertion: Data?) {
        self.payload = payload
        self.signature = signature
        self.assertion = assertion
    }
}

/// A nonce to sign, from `POST /v1/transfers/{id}/challenge`.
public struct SigningChallenge: Hashable, Sendable {
    public let nonce: String
    public let expiresAt: Date

    public init(nonce: String, expiresAt: Date) {
        self.nonce = nonce
        self.expiresAt = expiresAt
    }
}
