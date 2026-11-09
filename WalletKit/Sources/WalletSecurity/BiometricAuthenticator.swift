import Domain
import Foundation

/// Face ID or Touch ID. `DeviceBiometrics` is the real one; tests use a fake.
public protocol BiometricAuthenticator: Sendable {
    func isAvailable() -> Bool

    /// An opaque value that changes whenever faces or fingers are added or removed, or `nil`
    /// when biometrics aren't available. Reading it never shows a prompt.
    func enrollmentState() -> Data?

    /// Shows the system prompt. Returns the enrolment state of the context that just
    /// succeeded, so the caller can check it wasn't changed (ADR-019).
    func authenticate(reason: String) async throws(AuthError) -> Data?
}
