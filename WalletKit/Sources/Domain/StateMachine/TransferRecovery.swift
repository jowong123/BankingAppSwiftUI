/// What the outbox does next for a transfer that hasn't finished: the rule for an unknown
/// outcome (SPEC section 10, Phase 6 carry-over).
///
/// A pure function, like `TransferStateMachine`: the outbox owns the state and the calls.
/// - Authorised: create it. Repeating a create is safe, so after a crash, a timeout or a
///   404 ("still in flight") the create is simply sent again with the same ID.
/// - Submitted: confirm it. The create landed and the confirm may or may not have; a
///   repeat returns the transfer.
/// - Processing: ask for the status until it settles.
public enum TransferRecovery {
    public enum Step: Hashable, Sendable {
        case create
        case confirm
        case poll
        /// Nothing left to do.
        case done
    }

    public static func step(for state: TransferState) -> Step {
        switch state {
        case .authorised: .create
        case .submitted: .confirm
        case .processing: .poll
        case .draft, .quoted, .expired, .completed, .failed: .done
        }
    }

    /// The events that bring the app's state in line with the server's. Several when the
    /// server is ahead, e.g. after a crash the server may already report `completed` for a
    /// transfer the app still has as `authorised`. Empty when nothing changes.
    public static func events(
        from state: TransferState,
        to remote: RemoteTransferStatus
    ) -> [TransferEvent] {
        switch (state, remote) {
        case (.authorised, .awaitingConfirmation):
            [.confirmSent]
        case (.authorised, .processing):
            [.confirmSent, .serverAccepted]
        case (.authorised, .completed):
            [.confirmSent, .serverAccepted, .settled]
        // Refused or declined: the reason is in `failed`, and no money moved either way.
        case (.authorised, .failed), (.submitted, .failed):
            [.rejected]
        case (.submitted, .processing):
            [.serverAccepted]
        case (.submitted, .completed):
            [.serverAccepted, .settled]
        case (.processing, .completed):
            [.settled]
        case (.processing, .failed):
            [.declined]
        default:
            []
        }
    }

    /// The failure to record for a definite refusal of `step`. A refused confirm leaves the
    /// transfer unconfirmed, so no money moved either way.
    public static func refusalEvent(at state: TransferState) -> TransferEvent? {
        switch state {
        case .authorised, .submitted: .rejected
        default: nil
        }
    }
}
