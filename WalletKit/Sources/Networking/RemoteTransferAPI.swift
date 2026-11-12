import Domain
import Foundation

/// `TransferAPI` over the Wallet API, for the outbox. Every failure is sorted into what
/// the outbox's recovery rule needs (`TransferRecovery`): refused, not found, already
/// exists, or unknown. Anything not definitely refused is unknown, never failed (SPEC
/// section 5): the outbox asks again.
public struct RemoteTransferAPI: TransferAPI {
    private let api: WalletAPI

    public init(api: WalletAPI) {
        self.api = api
    }

    public func create(_ draft: TransferDraft) async throws(TransferAPIError) -> RemoteTransferStatus {
        do {
            return try await api.createTransfer(
                id: draft.id,
                quoteID: draft.quote.id,
                recipientID: draft.recipient.id,
                sourceAccountID: draft.sourceAccountID
            ).remoteStatus
        } catch {
            // On create, 404 is about the quote, recipient or account: a refusal.
            throw error.transferAPIError(notFound: .rejected(.rejected))
        }
    }

    public func confirm(id: UUID) async throws(TransferAPIError) -> RemoteTransferStatus {
        do {
            return try await api.confirmTransfer(id: id).remoteStatus
        } catch {
            throw error.transferAPIError(notFound: .notFound)
        }
    }

    public func status(id: UUID) async throws(TransferAPIError) -> RemoteTransferStatus {
        do {
            return try await api.transfer(id: id.uuidString.lowercased()).remoteStatus
        } catch {
            throw error.transferAPIError(notFound: .notFound)
        }
    }
}

extension APIError {
    /// Codes that mean "a transfer with this ID is already there": fetch it, don't fail it.
    static let transferExistsCodes: Set<String> = ["transfer_exists", "idempotency_mismatch"]

    /// - Parameter notFound: what a 404 means for this call.
    func transferAPIError(notFound: TransferAPIError) -> TransferAPIError {
        switch self {
        case .server(_, let code, _, _) where Self.transferExistsCodes.contains(code):
            .exists
        case .server(404, _, _, _), .http(404):
            notFound
        case .server(_, let code, _, _) where isDefiniteRejection:
            .rejected(TransferFailure(serverCode: code))
        case .invalidRequest:
            .rejected(.rejected)
        case .unauthorized:
            .sessionExpired
        case .cancelled:
            .cancelled
        default:
            .outcomeUnknown
        }
    }
}
