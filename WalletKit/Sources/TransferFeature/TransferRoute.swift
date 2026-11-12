import Domain

/// The screens pushed after the recipient list.
public enum TransferRoute: Hashable, Sendable {
    case amount(Recipient)
    case review(Recipient, FXQuote)
}
