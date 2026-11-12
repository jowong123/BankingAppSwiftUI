import Domain

/// Everything the auth flow needs, as Domain protocols. `AppEnvironment` passes
/// `SessionStore`; tests and previews pass fakes.
public struct AuthDependencies: Sendable {
    public let session: any SessionManaging
    /// Whether a transfer is still sending. Signing out deletes the outbox, so the lock
    /// screen asks first.
    public let hasPendingTransfers: @Sendable () async -> Bool

    public init(
        session: any SessionManaging,
        hasPendingTransfers: @escaping @Sendable () async -> Bool = {
            false
        }
    ) {
        self.session = session
        self.hasPendingTransfers = hasPendingTransfers
    }
}
