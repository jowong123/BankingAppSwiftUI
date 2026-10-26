/// Where a transfer is in its lifecycle. See the state diagram in docs/SPEC.md section 5.
public enum TransferState: String, CaseIterable, Hashable, Sendable {
    case draft
    case quoted
    case expired
    case authorised
    case submitted
    case processing
    case completed
    case failed

    /// Completed and Failed accept no further events.
    public var isTerminal: Bool {
        switch self {
        case .completed, .failed: true
        default: false
        }
    }
}

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

public enum TransferTransitionError: Error, Equatable, Sendable {
    case invalid(from: TransferState, event: TransferEvent)
}
