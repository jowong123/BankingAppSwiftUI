import Domain
import Foundation

/// Used only if the build has no valid `WalletAPIBaseURL`. The outbox treats every call as
/// an unknown outcome and waits, as it would for a server that can't be reached.
struct UnconfiguredTransferAPI: TransferAPI {
    func create(_ draft: TransferDraft) async throws(TransferAPIError) -> RemoteTransferStatus {
        throw .outcomeUnknown
    }

    func confirm(id: UUID) async throws(TransferAPIError) -> RemoteTransferStatus {
        throw .outcomeUnknown
    }

    func status(id: UUID) async throws(TransferAPIError) -> RemoteTransferStatus {
        throw .outcomeUnknown
    }
}
