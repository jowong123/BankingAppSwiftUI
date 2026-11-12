/// Why the server refused or declined a transfer. No money left the account in any of these.
public enum TransferFailure: String, Hashable, Sendable, CaseIterable {
    /// The quote ran out before the server created the transfer.
    case quoteExpired
    /// The quote was already used by another transfer.
    case quoteUsed
    case insufficientFunds
    /// Declined at settlement; the debit was refunded.
    case declined
    /// Any other refusal (a recipient or account that no longer exists).
    case rejected

    /// The server's reason code, e.g. `insufficient_funds`. Unknown codes are `.rejected`.
    public init(serverCode: String?) {
        switch serverCode {
        case "quote_expired": self = .quoteExpired
        case "quote_used": self = .quoteUsed
        case "insufficient_funds": self = .insufficientFunds
        case "declined": self = .declined
        default: self = .rejected
        }
    }
}
