#if DEBUG
    import Domain
    import Foundation
    import WalletSecurity

    /// UI tests use the PIN: Face ID on the simulator needs manual enrolment. Debug only.
    struct NoBiometrics: BiometricAuthenticator {
        func isAvailable() -> Bool {
            false
        }

        func enrollmentState() -> Data? {
            nil
        }

        func authenticate(reason: String) async throws(AuthError) -> Data? {
            throw .biometryUnavailable
        }
    }
#endif
