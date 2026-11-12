#if DEBUG
    import Domain
    import Foundation

    /// The outbox's server calls against `MockBank` for `-mockServer`. `-transferDelay <s>`
    /// slows every call, so a UI test can kill the app mid-transfer. Debug only.
    struct MockTransferAPI: TransferAPI {
        let bank: MockBank
        let delay: Duration

        func create(_ draft: TransferDraft) async throws(TransferAPIError) -> RemoteTransferStatus {
            try await simulateNetwork()
            return await bank.create(draft)
        }

        func confirm(id: UUID) async throws(TransferAPIError) -> RemoteTransferStatus {
            try await simulateNetwork()
            return await bank.confirm(id)
        }

        func status(id: UUID) async throws(TransferAPIError) -> RemoteTransferStatus {
            try await simulateNetwork()
            return await bank.status(id)
        }

        private func simulateNetwork() async throws(TransferAPIError) {
            do {
                try await Task.sleep(for: delay)
            } catch {
                throw .cancelled
            }
        }
    }
#endif
