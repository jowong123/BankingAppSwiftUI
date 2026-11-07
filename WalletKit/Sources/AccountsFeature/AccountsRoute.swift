import Domain

/// Screens pushed inside the Accounts flow. The list is the root, so it has no case.
public enum AccountsRoute: Hashable, Sendable {
    /// By ID, so the route stays the same whatever the balance is, and deep links can
    /// build it. The detail screen re-reads the balance itself.
    case accountDetail(accountID: Account.ID)
}
