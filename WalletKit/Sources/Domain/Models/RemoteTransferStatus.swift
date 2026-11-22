/// A transfer's status as the server reports it (`GET /v1/transfers/{id}`).
public enum RemoteTransferStatus: Hashable, Sendable {
    /// Created; the confirm hasn't arrived yet.
    case awaitingConfirmation
    /// Confirmed and debited; settlement pending.
    case processing
    case completed
    case failed(TransferFailure)
    /// A status this app version doesn't know. Treated as still in progress.
    case unknown

    /// The reason, for `failed`.
    public var failure: TransferFailure? {
        guard case .failed(let reason) = self else {
            return nil
        }
        return reason
    }
}
