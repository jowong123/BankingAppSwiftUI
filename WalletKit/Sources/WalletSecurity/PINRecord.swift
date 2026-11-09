import Foundation

/// What is stored for the PIN, as one Keychain item: never the PIN itself (ADR-019).
struct PINRecord: Codable, Hashable, Sendable {
    static let maxAttempts = 5

    let salt: Data
    let hash: Data
    let iterations: Int
    /// Saved *before* each check, so a failed write or a killed app can't give a free guess.
    /// Zero means the session must be wiped, even if an earlier wipe failed.
    var attemptsLeft = PINRecord.maxAttempts
    /// The Face ID enrolment when the PIN was last proven. If it changes (a face or finger
    /// added), Face ID is refused until the PIN is entered again.
    var biometricState: Data?
}
