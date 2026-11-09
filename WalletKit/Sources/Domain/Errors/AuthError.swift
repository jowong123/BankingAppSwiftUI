/// Why a sign-in, unlock or token refresh failed, in terms the auth screens can act on.
public enum AuthError: Error, Hashable, Sendable {
    /// Wrong email or password.
    case invalidCredentials
    /// No connection, or it timed out.
    case offline
    /// The server failed or is down.
    case unavailable
    /// The refresh token was refused: the user must sign in again.
    case sessionExpired
    /// The PIN isn't six digits.
    case invalidPIN
    /// Wrong PIN; the session survives `attemptsLeft` more tries.
    case wrongPIN(attemptsLeft: Int)
    /// The last allowed PIN attempt failed: the session was wiped and the user is signed out.
    case tooManyAttempts
    /// Face ID isn't set up on this device, or the app isn't allowed to use it.
    case biometryUnavailable
    /// Face ID didn't recognise the user. The PIN still works.
    case biometryFailed
    /// Faces or fingerprints were added or removed since the PIN was set. Face ID is off
    /// until the PIN is entered, so someone who adds their own face can't get in.
    case biometryChanged
    /// The secure storage couldn't be read or written (e.g. the device is locked).
    case storageUnavailable
    /// The user or the system cancelled.
    case cancelled
}
