#if DEBUG
    import Domain
    import Foundation

    /// Recipients and quotes from `MockBank` for `-mockServer`. Debug only.
    struct MockTransfersRepository: TransfersRepository {
        let bank: MockBank
        let delay: Duration

        func recipients() async throws(TransferError) -> [Recipient] {
            try await simulateNetwork()
            return MockBank.recipients
        }

        func quote(sourceAmount: Money, targetCurrency: Currency) async throws(TransferError) -> FXQuote {
            try await simulateNetwork()
            return try await bank.quote(sourceAmount: sourceAmount, targetCurrency: targetCurrency)
        }

        private func simulateNetwork() async throws(TransferError) {
            do {
                try await Task.sleep(for: delay)
            } catch {
                throw .cancelled
            }
        }
    }
#endif
