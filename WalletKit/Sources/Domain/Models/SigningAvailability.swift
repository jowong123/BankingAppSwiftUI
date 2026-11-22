/// Whether this device can approve a transfer right now.
public enum SigningAvailability: Hashable, Sendable {
    case ready
    /// No Face ID or Touch ID was set up when this device was bound, so there is no signing
    /// key. Set it up, then sign in again.
    case biometryNotSetUp
    /// Faces or fingerprints changed since the key was made. The key is gone for good
    /// (`.biometryCurrentSet`); signing in again binds a new one (SPEC section 6).
    case keyInvalidated
}
