/// Shown above the sign-in form.
public enum SignInNotice: Hashable, Sendable {
    /// The server refused to renew the session.
    case sessionExpired
}
