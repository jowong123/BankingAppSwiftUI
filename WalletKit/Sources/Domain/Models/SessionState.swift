/// Where the user's session is. `AppCoordinator` shows a different root for each.
public enum SessionState: Hashable, Sendable {
    /// No tokens: show login.
    case signedOut
    /// Just logged in, no PIN yet: show "create PIN".
    case needsPIN
    /// Tokens and a PIN exist, but the user must prove it's them (Face ID or PIN).
    case locked
    /// The app's content is visible.
    case unlocked
}
