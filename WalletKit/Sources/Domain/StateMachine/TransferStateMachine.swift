/// The transfer state machine as a pure function: no clock, no I/O, no stored state.
///
/// Callers (the transfer outbox, view models) own the current state and persist each
/// result before acting on it. Keeping this pure means every (state, event) pair can be
/// tested exhaustively.
public enum TransferStateMachine {
    public static func next(
        _ state: TransferState,
        _ event: TransferEvent
    ) throws(TransferTransitionError) -> TransferState {
        guard let next = transitions[state]?[event] else {
            throw .invalid(from: state, event: event)
        }
        return next
    }

    /// Every arrow in the docs/SPEC.md section 5 diagram. Anything not listed is invalid.
    static let transitions: [TransferState: [TransferEvent: TransferState]] = [
        .draft: [.quoteReceived: .quoted],
        .quoted: [.quoteExpired: .expired, .authorised: .authorised],
        .expired: [.quoteReceived: .quoted],
        // `rejected` from Authorised: the server refused to create it (quote expired, not
        // enough money), so there is nothing to confirm.
        .authorised: [.confirmSent: .submitted, .rejected: .failed],
        .submitted: [.serverAccepted: .processing, .rejected: .failed],
        .processing: [.settled: .completed, .declined: .failed],
    ]
}

public enum TransferTransitionError: Error, Equatable, Sendable {
    case invalid(from: TransferState, event: TransferEvent)
}
