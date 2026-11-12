import Foundation

/// The three server calls the outbox makes for one transfer. Every one is safe to repeat:
/// the server keys a transfer on its ID (SPEC sections 5 and 7).
public protocol TransferAPI: Sendable {
    /// `POST /v1/transfers` with `Idempotency-Key` = `draft.id`. A repeat returns the
    /// existing transfer.
    func create(_ draft: TransferDraft) async throws(TransferAPIError) -> RemoteTransferStatus

    /// `POST /v1/transfers/{id}/confirm`. Moves the money. A repeat returns the status.
    func confirm(id: UUID) async throws(TransferAPIError) -> RemoteTransferStatus

    /// `GET /v1/transfers/{id}`.
    func status(id: UUID) async throws(TransferAPIError) -> RemoteTransferStatus
}
