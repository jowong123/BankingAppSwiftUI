import Domain

/// Everything the Accounts flow needs, as Domain protocols. `AppEnvironment` passes the
/// real implementations; tests and previews pass fakes.
public struct AccountsDependencies: Sendable {
    public let repository: any AccountsRepository

    public init(repository: any AccountsRepository) {
        self.repository = repository
    }
}
