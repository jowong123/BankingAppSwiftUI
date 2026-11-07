/// Something that happened to a transfer, which may move it to a new state.
public enum TransferEvent: String, CaseIterable, Hashable, Sendable {
    /// A quote arrived, either the first one (from Draft) or a re-quote (from Expired).
    case quoteReceived
    /// The 30 s quote lock ended before the user confirmed.
    case quoteExpired
    /// Face ID passed and the confirm payload was signed.
    case authorised
    /// The signed confirm request was sent.
    case confirmSent
    /// The server accepted the transfer; settlement is pending.
    case serverAccepted
    /// The server rejected the confirm request.
    case rejected
    /// Settlement finished.
    case settled
    /// Settlement was declined after acceptance.
    case declined
}
