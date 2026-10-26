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
        switch (state, event) {
        case (.draft, .quoteReceived): .quoted
        case (.quoted, .quoteExpired): .expired
        case (.expired, .quoteReceived): .quoted
        case (.quoted, .authorised): .authorised
        case (.authorised, .confirmSent): .submitted
        case (.submitted, .serverAccepted): .processing
        case (.submitted, .rejected): .failed
        case (.processing, .settled): .completed
        case (.processing, .declined): .failed
        default: throw .invalid(from: state, event: event)
        }
    }
}
