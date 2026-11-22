/// Screens pushed inside the sign-in flow. None yet: sign in, create PIN and unlock are
/// separate roots chosen by `AppCoordinator` from the session state, so there is no way
/// back to the sign-in form while a session waits for its PIN.
public enum AuthRoute: Hashable, Sendable {}
