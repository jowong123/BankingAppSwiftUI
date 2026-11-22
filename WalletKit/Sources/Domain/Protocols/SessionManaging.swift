/// The session as AuthFeature and `AppCoordinator` see it. Every call returns the new
/// state, so the caller never has to ask separately. `SessionStore` implements it.
public protocol SessionManaging: Sendable {
    /// Reads what is stored at launch: signed out, needs a PIN, or locked. Never unlocked.
    func restore() async -> SessionState

    func currentState() async -> SessionState

    func login(email: String, password: String) async throws(AuthError) -> SessionState

    /// `pin` must be six digits. Only valid right after login (`.needsPIN`).
    func createPIN(_ pin: String) async throws(AuthError) -> SessionState

    func unlock(pin: String) async throws(AuthError) -> SessionState

    /// `reason` is shown in the system prompt where the device uses Touch ID.
    func unlockWithBiometrics(reason: String) async throws(AuthError) -> SessionState

    func canUseBiometrics() async -> Bool

    /// Hides the content until Face ID or the PIN succeeds. The tokens stay.
    func lock() async -> SessionState

    /// Wipes the tokens and the PIN.
    func signOut() async -> SessionState

    /// The current state, then every change, including ones nobody asked for: a refused
    /// token refresh in the background signs the user out (SPEC section 6).
    func stateUpdates() async -> AsyncStream<SessionState>
}
