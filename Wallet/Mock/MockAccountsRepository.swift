#if DEBUG
    import Domain
    import Foundation

    /// Accounts and history from `MockBank`, for UI tests and previews of the whole app
    /// (`-mockServer`, SPEC section 8). Debug only. Add `-simulateOffline` to see the offline state.
    struct MockAccountsRepository: AccountsRepository {
        static let pageSize = 20

        let bank: MockBank
        let isOffline: Bool
        let delay: Duration

        init(bank: MockBank = MockBank(), isOffline: Bool, delay: Duration) {
            self.bank = bank
            self.isOffline = isOffline
            self.delay = delay
        }

        func accounts() async throws(DataSourceError) -> [Account] {
            try await simulateNetwork()
            return await bank.accounts()
        }

        /// The cursor is the offset of the next page, like an opaque server cursor.
        func transactions(accountID: String, cursor: String?) async throws(DataSourceError) -> TransactionPage {
            try await simulateNetwork()
            let items = await bank.transactions(accountID)
            let start = cursor.flatMap(Int.init) ?? 0
            guard start >= 0, start <= items.count else {
                throw .invalidData
            }
            let end = min(start + Self.pageSize, items.count)
            return TransactionPage(items: Array(items[start..<end]), nextCursor: end < items.count ? String(end) : nil)
        }

        private func simulateNetwork() async throws(DataSourceError) {
            do {
                try await Task.sleep(for: delay)
            } catch {
                throw .cancelled
            }
            if isOffline {
                throw .offline
            }
        }
    }
#endif
