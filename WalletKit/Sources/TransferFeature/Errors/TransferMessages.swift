import Domain

/// What the send-money screens show for a `TransferError`.
enum TransferMessages {
    /// `nil` for cancellation: the screen went away, so there is nothing to show.
    static func userFacing(_ error: TransferError) -> UserFacingError? {
        switch error {
        case .offline:
            UserFacingError(
                title: TransferStrings.offlineTitle, message: TransferStrings.offlineMessage, canRetry: true)
        case .unavailable:
            UserFacingError(
                title: TransferStrings.unavailableTitle, message: TransferStrings.unavailableMessage, canRetry: true)
        case .sessionExpired:
            UserFacingError(
                title: TransferStrings.sessionExpiredTitle,
                message: TransferStrings.sessionExpiredMessage,
                canRetry: false
            )
        case .amountNotAllowed:
            UserFacingError(
                title: TransferStrings.amountNotAllowedTitle,
                message: TransferStrings.amountNotAllowedMessage,
                canRetry: false
            )
        case .invalidData:
            UserFacingError(
                title: TransferStrings.failedTitle, message: TransferStrings.failedMessage, canRetry: true)
        case .storageUnavailable:
            UserFacingError(
                title: TransferStrings.storageTitle, message: TransferStrings.storageMessage, canRetry: true)
        case .cancelled:
            nil
        }
    }
}
