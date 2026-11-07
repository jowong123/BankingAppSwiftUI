#if DEBUG
    import Domain
    import Foundation

    /// In-memory accounts with the same data as the backend seed (`backend/.../SeedData.swift`).
    ///
    /// Phase 4 runs on fake data: there is no session to call the real API until Phase 5,
    /// which replaces this with `RemoteAccountsRepository`. Fake money only, nothing stored.
    /// Launch with `-simulateOffline` to see the offline state.
    struct SandboxAccountsRepository: AccountsRepository {
        static let pageSize = 20

        let isOffline: Bool
        let delay: Duration
        private let accountsByID: [String: Account]
        private let accountOrder: [String]
        private let history: [String: [AccountTransaction]]

        init(isOffline: Bool, delay: Duration, now: Date = .now) {
            self.isOffline = isOffline
            self.delay = delay
            let accounts = [
                Account(id: "acc_sgd", balance: Money(amountMinor: 1_250_000, currency: .sgd), updatedAt: now),
                Account(id: "acc_usd", balance: Money(amountMinor: 320_000, currency: .usd), updatedAt: now),
                Account(id: "acc_jpy", balance: Money(amountMinor: 150_000, currency: .jpy), updatedAt: now),
                Account(id: "acc_kwd", balance: Money(amountMinor: 120_500, currency: .kwd), updatedAt: now),
            ]
            self.accountOrder = accounts.map(\.id)
            self.accountsByID = Dictionary(
                uniqueKeysWithValues: accounts.map {
                    ($0.id, $0)
                })
            self.history = Self.seedHistory(now: now)
        }

        func accounts() async throws(DataSourceError) -> [Account] {
            try await simulateNetwork()
            return accountOrder.compactMap {
                accountsByID[$0]
            }
        }

        /// The cursor is the offset of the next page, like an opaque server cursor.
        func transactions(accountID: String, cursor: String?) async throws(DataSourceError) -> TransactionPage {
            try await simulateNetwork()
            let items = history[accountID] ?? []
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

        /// Newest first, one hour apart, matching the backend seed's amounts and merchants.
        private static func seedHistory(now: Date) -> [String: [AccountTransaction]] {
            let merchants = ["Kopi Corner", "MRT Top-up", "FairPrice", "Grab", "Salary", "Netflix", "Uniqlo", "Refund"]
            var sgd: [AccountTransaction] = []
            for index in (0..<45).reversed() {
                let merchant = merchants[index % merchants.count]
                let incoming = merchant == "Salary" || merchant == "Refund"
                let amount = Int64(350 + (index * 137) % 9_000)
                sgd.append(
                    AccountTransaction(
                        id: "txn_sgd_\(index)",
                        accountID: "acc_sgd",
                        amount: Money(amountMinor: incoming ? amount * 10 : -amount, currency: .sgd),
                        description: merchant,
                        createdAt: now.addingTimeInterval(TimeInterval(-(45 - index) * 3_600))
                    )
                )
            }
            func history(_ accountID: String, _ currency: Currency, _ items: [SeedEntry]) -> [AccountTransaction] {
                items.map { item in
                    AccountTransaction(
                        id: item.id,
                        accountID: accountID,
                        amount: Money(amountMinor: item.minor, currency: currency),
                        description: item.text,
                        createdAt: now.addingTimeInterval(TimeInterval(-item.hoursAgo * 3_600))
                    )
                }
            }
            return [
                "acc_sgd": sgd,
                "acc_usd": history(
                    "acc_usd", .usd,
                    [
                        SeedEntry(id: "txn_usd_2", minor: 120_000, text: "Transfer in", hoursAgo: 2),
                        SeedEntry(id: "txn_usd_1", minor: -4_599, text: "Amazon", hoursAgo: 5),
                    ]),
                "acc_jpy": history(
                    "acc_jpy", .jpy,
                    [
                        SeedEntry(id: "txn_jpy_2", minor: 50_000, text: "Transfer in", hoursAgo: 3),
                        SeedEntry(id: "txn_jpy_1", minor: -1_200, text: "Lawson", hoursAgo: 6),
                    ]),
                "acc_kwd": history(
                    "acc_kwd", .kwd, [SeedEntry(id: "txn_kwd_1", minor: -2_750, text: "Talabat", hoursAgo: 4)]),
            ]
        }
    }

    /// One seeded non-SGD transaction, newest first per account.
    private struct SeedEntry {
        let id: String
        let minor: Int64
        let text: String
        let hoursAgo: Int
    }
#endif
