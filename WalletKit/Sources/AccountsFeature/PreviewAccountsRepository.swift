#if DEBUG
    import Domain
    import Foundation

    /// Fixed data for SwiftUI previews. Not compiled into release builds.
    struct PreviewAccountsRepository: AccountsRepository {
        var failure: DataSourceError?

        static let sampleAccounts = [
            Account(id: "acc_sgd", balance: Money(amountMinor: 1_250_000, currency: .sgd), updatedAt: .now),
            Account(id: "acc_usd", balance: Money(amountMinor: 320_000, currency: .usd), updatedAt: .now),
            Account(id: "acc_jpy", balance: Money(amountMinor: 150_000, currency: .jpy), updatedAt: .now),
            Account(id: "acc_kwd", balance: Money(amountMinor: 120_500, currency: .kwd), updatedAt: .now),
        ]

        func accounts() async throws(DataSourceError) -> [Account] {
            if let failure {
                throw failure
            }
            return Self.sampleAccounts
        }

        func transactions(accountID: String, cursor: String?) async throws(DataSourceError) -> TransactionPage {
            if let failure {
                throw failure
            }
            let items = [
                ("Kopi Corner", Int64(-450)), ("Salary", 520_000), ("Grab", -1_820), ("Refund", 2_500),
            ]
            .enumerated()
            .map { index, item in
                AccountTransaction(
                    id: "txn_\(index)",
                    accountID: accountID,
                    amount: Money(amountMinor: item.1, currency: .sgd),
                    description: item.0,
                    createdAt: Date(timeIntervalSinceNow: Double(-3_600 * index))
                )
            }
            return TransactionPage(items: items, nextCursor: nil)
        }
    }
#endif
