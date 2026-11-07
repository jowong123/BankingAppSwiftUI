/// Reads the user's accounts and their history.
///
/// Declared in Domain so AccountsFeature can use it without importing `Networking`
/// (ADR-004). `RemoteAccountsRepository` in Networking implements it; `AppEnvironment`
/// injects it. Online only: no account data is stored on the device (ADR-017).
public protocol AccountsRepository: Sendable {
    func accounts() async throws(DataSourceError) -> [Account]

    /// `cursor` is `nil` for the first (newest) page, then the previous page's `nextCursor`.
    func transactions(accountID: String, cursor: String?) async throws(DataSourceError) -> TransactionPage
}
