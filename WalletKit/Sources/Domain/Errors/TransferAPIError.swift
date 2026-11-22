/// What a transfer call to the server told the outbox, in the terms its recovery rule
/// needs (SPEC section 10, Phase 6 carry-over).
public enum TransferAPIError: Error, Hashable, Sendable {
    /// The server definitely refused this call and changed nothing.
    case rejected(TransferFailure)
    /// No transfer with this ID (yet): the create may still be in flight.
    case notFound
    /// A transfer with this ID already exists (`transfer_exists`, `idempotency_mismatch`).
    case exists
    /// The call may or may not have worked: a timeout, a dropped connection, a 5xx. Never
    /// a failure: the outbox asks again later.
    case outcomeUnknown
    /// The session can't be renewed. The outbox stops until the user signs in again.
    case sessionExpired
    case cancelled
}
