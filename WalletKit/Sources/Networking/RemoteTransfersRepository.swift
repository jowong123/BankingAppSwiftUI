import Domain

/// `TransfersRepository` over the Wallet API: recipients and quotes for the send-money
/// screens. Turns `APIError` into `TransferError`, so TransferFeature never sees HTTP.
public struct RemoteTransfersRepository: TransfersRepository {
    private let api: WalletAPI

    public init(api: WalletAPI) {
        self.api = api
    }

    public func recipients() async throws(TransferError) -> [Recipient] {
        do {
            return try await api.recipients()
        } catch {
            throw error.transferError
        }
    }

    public func quote(sourceAmount: Money, targetCurrency: Currency) async throws(TransferError) -> FXQuote {
        do {
            return try await api.createQuote(sourceAmount: sourceAmount, targetCurrency: targetCurrency)
        } catch {
            // The quote route refuses an amount below the fee or above the limit with 422.
            if case .server(_, "invalid_request", _, _) = error {
                throw .amountNotAllowed
            }
            throw error.transferError
        }
    }
}

extension APIError {
    /// What a failed read or quote means for the send-money screens.
    var transferError: TransferError {
        switch dataSourceError {
        case .offline:
            .offline
        case .unavailable:
            .unavailable
        case .sessionExpired:
            .sessionExpired
        case .invalidData:
            .invalidData
        case .cancelled:
            .cancelled
        }
    }
}
