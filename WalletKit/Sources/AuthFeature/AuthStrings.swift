import Foundation

/// Every user-visible string in the feature, read from `Resources/en.lproj/Localizable.strings`.
/// English only (SPEC section 2). Code uses these properties, never the keys.
enum AuthStrings {
    static var signInTitle: String {
        text("auth.signIn.title")
    }
    static var email: String {
        text("auth.signIn.email")
    }
    static var password: String {
        text("auth.signIn.password")
    }
    static var signIn: String {
        text("auth.signIn.submit")
    }
    static var sessionExpired: String {
        text("auth.signIn.sessionExpired")
    }
    static var createPINTitle: String {
        text("auth.createPIN.title")
    }
    static var createPINEnter: String {
        text("auth.createPIN.enter")
    }
    static var createPINConfirm: String {
        text("auth.createPIN.confirm")
    }
    static var unlockTitle: String {
        text("auth.unlock.title")
    }
    static var unlockPrompt: String {
        text("auth.unlock.prompt")
    }
    static var useFaceID: String {
        text("auth.unlock.useFaceID")
    }
    static var biometricReason: String {
        text("auth.unlock.biometricReason")
    }
    static var signOut: String {
        text("auth.unlock.signOut")
    }
    static var tooManyAttemptsTitle: String {
        text("auth.unlock.tooManyAttempts.title")
    }
    static var tooManyAttemptsMessage: String {
        text("auth.unlock.tooManyAttempts.message")
    }
    static var okay: String {
        text("auth.ok")
    }
    static var invalidCredentialsTitle: String {
        text("auth.error.invalidCredentials.title")
    }
    static var invalidCredentialsMessage: String {
        text("auth.error.invalidCredentials.message")
    }
    static var offlineTitle: String {
        text("auth.error.offline.title")
    }
    static var offlineMessage: String {
        text("auth.error.offline.message")
    }
    static var unavailableTitle: String {
        text("auth.error.unavailable.title")
    }
    static var unavailableMessage: String {
        text("auth.error.unavailable.message")
    }
    static var sessionExpiredTitle: String {
        text("auth.error.sessionExpired.title")
    }
    static var sessionExpiredMessage: String {
        text("auth.error.sessionExpired.message")
    }
    static var storageTitle: String {
        text("auth.error.storage.title")
    }
    static var storageMessage: String {
        text("auth.error.storage.message")
    }
    static var invalidPINTitle: String {
        text("auth.error.invalidPIN.title")
    }
    static var invalidPINMessage: String {
        text("auth.error.invalidPIN.message")
    }
    static var pinMismatchTitle: String {
        text("auth.error.pinMismatch.title")
    }
    static var pinMismatchMessage: String {
        text("auth.error.pinMismatch.message")
    }
    static var wrongPINTitle: String {
        text("auth.error.wrongPIN.title")
    }
    static var biometryFailedTitle: String {
        text("auth.error.biometryFailed.title")
    }
    static var biometryUnavailableTitle: String {
        text("auth.error.biometryUnavailable.title")
    }
    static var biometryMessage: String {
        text("auth.error.biometry.message")
    }
    static var biometryChangedTitle: String {
        text("auth.error.biometryChanged.title")
    }
    static var biometryChangedMessage: String {
        text("auth.error.biometryChanged.message")
    }

    static func wrongPINMessage(attemptsLeft: Int) -> String {
        attemptsLeft == 1
            ? text("auth.error.wrongPIN.one")
            : String(format: text("auth.error.wrongPIN.other"), attemptsLeft)
    }

    /// A missing key comes back as the key itself; `AuthStringsTests` catches that.
    private static func text(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    }
}
