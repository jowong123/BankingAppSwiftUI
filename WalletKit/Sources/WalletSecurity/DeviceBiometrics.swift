import Domain
import Foundation
import LocalAuthentication

/// `LocalAuthentication`, biometrics only: the device passcode is not accepted here,
/// because the app's own PIN is the fallback (ADR-019).
public struct DeviceBiometrics: BiometricAuthenticator {
    public init() {}

    public func isAvailable() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    public func enrollmentState() -> Data? {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return nil
        }
        return context.evaluatedPolicyDomainState
    }

    public func authenticate(reason: String) async throws(AuthError) -> Data? {
        // A fresh context each time, so an earlier success is never reused.
        let context = LAContext()
        context.localizedFallbackTitle = ""
        do {
            _ = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch let error as LAError {
            throw Self.authError(for: error.code)
        } catch {
            throw .biometryFailed
        }
        return context.evaluatedPolicyDomainState
    }

    static func authError(for code: LAError.Code) -> AuthError {
        switch code {
        case .userCancel, .appCancel, .systemCancel, .userFallback:
            .cancelled
        case .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout, .passcodeNotSet:
            .biometryUnavailable
        default:
            .biometryFailed
        }
    }
}
