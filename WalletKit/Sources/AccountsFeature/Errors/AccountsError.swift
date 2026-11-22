import Domain
import Foundation

/// Turns a data source failure into what the Accounts screens show.
enum AccountsError {
    /// `nil` for cancellation: the screen went away, so there is nothing to show.
    static func userFacing(_ error: DataSourceError) -> UserFacingError? {
        switch error {
        case .offline:
            UserFacingError(
                title: AccountsStrings.offlineTitle, message: AccountsStrings.offlineMessage, canRetry: true)
        case .unavailable:
            UserFacingError(
                title: AccountsStrings.unavailableTitle,
                message: AccountsStrings.unavailableMessage,
                canRetry: true
            )
        case .invalidData:
            UserFacingError(title: AccountsStrings.failedTitle, message: AccountsStrings.failedMessage, canRetry: true)
        case .sessionExpired:
            UserFacingError(
                title: AccountsStrings.sessionExpiredTitle,
                message: AccountsStrings.sessionExpiredMessage,
                canRetry: false
            )
        case .cancelled:
            nil
        }
    }
}
