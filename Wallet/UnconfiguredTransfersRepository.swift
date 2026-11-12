import Domain

/// Used only if the build has no valid `WalletAPIBaseURL`: nothing can be quoted, so no
/// transfer can start, and the screens say the service can't be reached.
struct UnconfiguredTransfersRepository: TransfersRepository {
    func recipients() async throws(TransferError) -> [Recipient] {
        throw .unavailable
    }

    func quote(sourceAmount: Money, targetCurrency: Currency) async throws(TransferError) -> FXQuote {
        throw .unavailable
    }
}
