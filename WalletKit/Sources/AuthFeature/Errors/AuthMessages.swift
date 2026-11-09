import Domain

/// What each auth screen shows for an `AuthError`: a short title and what to do next.
enum AuthMessages {
    /// `nil` when there is nothing to show: the user cancelled, or the screen handles the
    /// case itself (too many attempts shows an alert, then signs out).
    static func userFacing(_ error: AuthError) -> UserFacingError? {
        switch error {
        case .invalidCredentials:
            UserFacingError(
                title: AuthStrings.invalidCredentialsTitle,
                message: AuthStrings.invalidCredentialsMessage,
                canRetry: false
            )
        case .offline:
            UserFacingError(title: AuthStrings.offlineTitle, message: AuthStrings.offlineMessage, canRetry: true)
        case .unavailable:
            UserFacingError(
                title: AuthStrings.unavailableTitle, message: AuthStrings.unavailableMessage, canRetry: true)
        case .sessionExpired:
            UserFacingError(
                title: AuthStrings.sessionExpiredTitle, message: AuthStrings.sessionExpiredMessage, canRetry: false)
        case .storageUnavailable:
            UserFacingError(title: AuthStrings.storageTitle, message: AuthStrings.storageMessage, canRetry: true)
        case .invalidPIN, .wrongPIN:
            pinError(error)
        case .biometryFailed, .biometryUnavailable, .biometryChanged:
            biometryError(error)
        case .tooManyAttempts, .cancelled:
            nil
        }
    }

    /// The two PINs typed on "Create PIN" were different. Not an `AuthError`: nothing was
    /// sent to the session.
    static var pinMismatch: UserFacingError {
        UserFacingError(
            title: AuthStrings.pinMismatchTitle, message: AuthStrings.pinMismatchMessage, canRetry: false)
    }

    private static func pinError(_ error: AuthError) -> UserFacingError? {
        switch error {
        case .invalidPIN:
            UserFacingError(
                title: AuthStrings.invalidPINTitle, message: AuthStrings.invalidPINMessage, canRetry: false)
        case .wrongPIN(let attemptsLeft):
            UserFacingError(
                title: AuthStrings.wrongPINTitle,
                message: AuthStrings.wrongPINMessage(attemptsLeft: attemptsLeft),
                canRetry: false
            )
        default:
            nil
        }
    }

    /// Every Face ID problem points the user to the PIN.
    private static func biometryError(_ error: AuthError) -> UserFacingError? {
        switch error {
        case .biometryFailed:
            UserFacingError(
                title: AuthStrings.biometryFailedTitle, message: AuthStrings.biometryMessage, canRetry: false)
        case .biometryUnavailable:
            UserFacingError(
                title: AuthStrings.biometryUnavailableTitle, message: AuthStrings.biometryMessage, canRetry: false)
        case .biometryChanged:
            UserFacingError(
                title: AuthStrings.biometryChangedTitle,
                message: AuthStrings.biometryChangedMessage,
                canRetry: false
            )
        default:
            nil
        }
    }
}
