import CommonCrypto
import Foundation
import Security

/// Turns a PIN into something safe to store: PBKDF2-HMAC-SHA256 with a random 16-byte
/// salt (ADR-019). A six-digit PIN has only a million values, so the slow hash matters
/// only if the stored record leaks; the real protection is the attempt limit in
/// `SessionStore` plus the Keychain's this-device-only, when-unlocked access.
struct PINHasher: Sendable {
    /// OWASP's 2023 minimum for PBKDF2-HMAC-SHA256.
    static let defaultIterations = 600_000

    let iterations: Int

    init(iterations: Int = Self.defaultIterations) {
        self.iterations = iterations
    }

    func makeRecord(for pin: String) throws(SecureStoreError) -> PINRecord {
        let salt = try Self.randomSalt()
        return PINRecord(salt: salt, hash: try hash(pin, salt: salt, iterations: iterations), iterations: iterations)
    }

    /// Compares in constant time, so how long it takes says nothing about how close a guess was.
    func verify(_ pin: String, against record: PINRecord) throws(SecureStoreError) -> Bool {
        let candidate = try hash(pin, salt: record.salt, iterations: record.iterations)
        guard candidate.count == record.hash.count else {
            return false
        }
        var difference: UInt8 = 0
        for (lhs, rhs) in zip(candidate, record.hash) {
            difference |= lhs ^ rhs
        }
        return difference == 0
    }

    func hash(_ pin: String, salt: Data, iterations: Int) throws(SecureStoreError) -> Data {
        var derived = [UInt8](repeating: 0, count: 32)
        let password = pin.utf8.map {
            CChar(bitPattern: $0)
        }
        let status = salt.withUnsafeBytes { saltBytes in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                password,
                password.count,
                saltBytes.bindMemory(to: UInt8.self).baseAddress,
                salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                &derived,
                derived.count
            )
        }
        guard status == kCCSuccess else {
            throw SecureStoreError(status: status)
        }
        return Data(derived)
    }

    private static func randomSalt() throws(SecureStoreError) -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw SecureStoreError(status: status)
        }
        return Data(bytes)
    }
}
