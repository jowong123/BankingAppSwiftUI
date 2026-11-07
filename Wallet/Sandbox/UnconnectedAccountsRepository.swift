import Domain

/// What Release builds use until Phase 5 connects `RemoteAccountsRepository`: the sandbox
/// data and its launch-argument hooks are Debug only, so a shipped build never shows
/// invented balances. Every call reports the service as unavailable.
struct UnconnectedAccountsRepository: AccountsRepository {
    func accounts() async throws(DataSourceError) -> [Account] {
        throw .unavailable
    }

    func transactions(accountID: String, cursor: String?) async throws(DataSourceError) -> TransactionPage {
        throw .unavailable
    }
}
