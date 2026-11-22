import Domain

/// Used only if the build has no valid `WalletAPIBaseURL`: every call reports the service as
/// unavailable, so a misconfigured build fails closed instead of guessing a server.
struct UnconfiguredAccountsRepository: AccountsRepository {
    func accounts() async throws(DataSourceError) -> [Account] {
        throw .unavailable
    }

    func transactions(accountID: String, cursor: String?) async throws(DataSourceError) -> TransactionPage {
        throw .unavailable
    }
}
