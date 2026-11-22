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
