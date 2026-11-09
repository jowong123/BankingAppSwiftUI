/// Which screen the flow shows. `AppCoordinator` picks it from the session state.
public enum AuthStart: Hashable, Sendable {
    /// Email and password, optionally explaining why the user is here.
    case signIn(SignInNotice?)
    /// Signed in, no PIN yet.
    case createPIN
    /// Face ID or PIN for a saved session.
    case unlock
}
