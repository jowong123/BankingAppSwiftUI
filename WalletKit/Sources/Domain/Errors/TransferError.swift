/// Why a transfer step the user started (loading recipients, getting a quote, sending)
/// didn't happen. Once a transfer is in the outbox its problems become its `state`.
public enum TransferError: Error, Hashable, Sendable {
    /// No connection, or it timed out. Retrying later may work.
    case offline
    /// The server can't be reached or failed. Retrying later may work.
    case unavailable
    /// The session can't be renewed; the user must sign in again.
    case sessionExpired
    /// The server refused the amount: too small to cover the fee, or above the limit.
    case amountNotAllowed
    /// The response didn't make sense.
    case invalidData
    /// The transfer couldn't be saved on the device, so it wasn't sent.
    case storageUnavailable
    /// The caller cancelled, e.g. the screen went away. Not shown to the user.
    case cancelled
}
