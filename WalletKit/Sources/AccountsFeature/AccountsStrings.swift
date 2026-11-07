import Foundation

/// Every user-visible string in the feature, read from `Resources/en.lproj/Localizable.strings`.
/// English only (SPEC section 2). Code uses these properties, never the keys.
enum AccountsStrings {
    static var title: String {
        text("accounts.title")
    }
    static var noAccounts: String {
        text("accounts.empty")
    }
    static var couldNotUpdate: String {
        text("accounts.refreshFailed")
    }
    static var noTransactions: String {
        text("accounts.transactions.empty")
    }
    static var couldNotLoadMore: String {
        text("accounts.transactions.loadMoreFailed")
    }
    static var retry: String {
        text("accounts.retry")
    }
    static var offlineTitle: String {
        text("accounts.error.offline.title")
    }
    static var offlineMessage: String {
        text("accounts.error.offline.message")
    }
    static var failedTitle: String {
        text("accounts.error.failed.title")
    }
    static var failedMessage: String {
        text("accounts.error.failed.message")
    }
    static var sessionExpiredTitle: String {
        text("accounts.error.sessionExpired.title")
    }
    static var sessionExpiredMessage: String {
        text("accounts.error.sessionExpired.message")
    }

    /// A missing key comes back as the key itself; `AccountsStringsTests` catches that.
    private static func text(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    }
}
