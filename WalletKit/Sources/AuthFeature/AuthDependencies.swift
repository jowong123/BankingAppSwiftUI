import Domain

/// Everything the auth flow needs, as Domain protocols. `AppEnvironment` passes
/// `SessionStore`; tests and previews pass fakes.
public struct AuthDependencies: Sendable {
    public let session: any SessionManaging

    public init(session: any SessionManaging) {
        self.session = session
    }
}
