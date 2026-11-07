/// Why a read from a data source failed, in terms a feature can act on.
/// Implementations map their own errors (HTTP, decoding) to these.
public enum DataSourceError: Error, Hashable, Sendable {
    /// No connection, or it timed out. Retrying later may work.
    case offline
    /// The session can't be renewed; the user must sign in again.
    case sessionExpired
    /// The server failed or is down. Retrying later may work.
    case unavailable
    /// The response didn't make sense (unknown currency, bad data).
    case invalidData
    /// The caller cancelled, e.g. the screen went away. Not shown to the user.
    case cancelled
}
