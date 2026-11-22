/// Why the server refused or declined a transfer. No money left the account in any of these.
public enum TransferFailure: String, Hashable, Sendable, CaseIterable {
    /// The quote ran out before the server created the transfer.
    case quoteExpired
    /// The quote was already used by another transfer.
    case quoteUsed
    case insufficientFunds
    /// Declined at settlement; the debit was refunded.
    case declined
    /// The Face ID approval ran out (60 s) before the server got it, e.g. offline too long.
    case approvalExpired
    /// The server didn't accept the approval: the signature, the nonce or the App Attest
    /// assertion was refused, or this device can no longer sign.
    case notApproved
    /// Any other refusal (a recipient or account that no longer exists).
    case rejected

    /// The server's reason code, e.g. `insufficient_funds`. Unknown codes are `.rejected`.
    public init(serverCode: String?) {
        switch serverCode {
        case "quote_expired": self = .quoteExpired
        case "quote_used": self = .quoteUsed
        case "insufficient_funds": self = .insufficientFunds
        case "declined": self = .declined
        case "nonce_expired": self = .approvalExpired
        case "signature_required", "invalid_signature", "payload_mismatch", "invalid_nonce", "nonce_used",
            "assertion_invalid", "device_not_bound":
            self = .notApproved
        default: self = .rejected
        }
    }
}
