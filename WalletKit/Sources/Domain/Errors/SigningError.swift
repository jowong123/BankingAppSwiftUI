/// Why a transfer couldn't be approved with Face ID.
public enum SigningError: Error, Hashable, Sendable {
    /// No signing key: Face ID or Touch ID wasn't set up when this device was bound.
    case biometryNotSetUp
    /// Faces or fingerprints changed; the key no longer works. Sign in again.
    case keyInvalidated
    /// The user cancelled the Face ID prompt.
    case cancelled
    /// Face ID didn't recognise the user, or the key couldn't sign.
    case failed
}
