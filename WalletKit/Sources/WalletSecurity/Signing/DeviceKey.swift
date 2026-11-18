import Domain
import Foundation

/// The device's signing key: P-256, usable only after Face ID or Touch ID, and only while
/// the enrolment is the one it was made with (SPEC section 6, ADR-008).
///
/// `SecureEnclaveKey` is the real one. `SoftwareKey` stands in on the simulator, which has no
/// Secure Enclave (ADR-023).
public protocol DeviceKey: Sendable {
    /// `true` when Face ID or Touch ID is set up, so a key can be made. Never prompts.
    func canMake() -> Bool

    /// Makes a new key, replacing any old one, and returns its X9.63 public key.
    func make() throws(SigningError) -> Data

    /// Never prompts.
    func availability() -> SigningAvailability

    /// Shows the Face ID prompt with `reason`, then returns a DER ECDSA signature over
    /// SHA-256 of `message`.
    func sign(_ message: Data, reason: String) async throws(SigningError) -> Data

    func remove()
}

/// The Face ID enrolment a key was made under, kept beside it. If the enrolment changes,
/// the key counts as gone: the Secure Enclave key really is (`.biometryCurrentSet`), and the
/// simulator's stand-in behaves the same way.
struct KeyEnrollment: Sendable {
    let store: any SecureStore
    let biometrics: any BiometricAuthenticator

    static let storeKey = "device.keyEnrollment"

    func save() throws(SigningError) {
        guard let state = biometrics.enrollmentState() else {
            throw .biometryNotSetUp
        }
        do {
            try store.set(state, for: Self.storeKey)
        } catch {
            throw .failed
        }
    }

    /// `.ready` only if a key exists and the enrolment is unchanged.
    func availability(hasKey: Bool) -> SigningAvailability {
        guard hasKey else {
            return .biometryNotSetUp
        }
        guard let saved = try? store.data(for: Self.storeKey), let current = biometrics.enrollmentState(),
            saved == current
        else {
            return .keyInvalidated
        }
        return .ready
    }

    /// The enrolment of the prompt that just succeeded must be the saved one too: someone
    /// could add a face between the check and the prompt.
    func matches(_ authenticated: Data?) -> Bool {
        guard let authenticated, let saved = try? store.data(for: Self.storeKey) else {
            return false
        }
        return authenticated == saved
    }

    func remove() {
        try? store.remove(Self.storeKey)
    }
}
