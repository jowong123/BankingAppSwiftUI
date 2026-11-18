import CryptoKit
import Domain
import Foundation
import LocalAuthentication
import Security

/// The signing key in the Secure Enclave. The private key never leaves it: the Keychain holds
/// only CryptoKit's `dataRepresentation`, a handle that works on this device's Secure Enclave
/// and nowhere else.
///
/// Access control is `.privateKeyUsage` + `.biometryCurrentSet`: every signature needs Face ID
/// or Touch ID, and adding or removing a face or finger destroys the key for good, so a new
/// face can't approve transfers (SPEC section 6).
public struct SecureEnclaveKey: DeviceKey {
    private let store: any SecureStore
    private let enrollment: KeyEnrollment

    static let storeKey = "device.secureEnclaveKey"

    public init(store: any SecureStore, biometrics: any BiometricAuthenticator) {
        self.store = store
        enrollment = KeyEnrollment(store: store, biometrics: biometrics)
    }

    public func canMake() -> Bool {
        SecureEnclave.isAvailable && enrollment.biometrics.enrollmentState() != nil
    }

    public func make() throws(SigningError) -> Data {
        remove()
        guard canMake(),
            let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                [.privateKeyUsage, .biometryCurrentSet],
                nil
            )
        else {
            throw .biometryNotSetUp
        }
        do {
            let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
            try store.set(key.dataRepresentation, for: Self.storeKey)
            try enrollment.save()
            return key.publicKey.x963Representation
        } catch {
            remove()
            throw .failed
        }
    }

    public func availability() -> SigningAvailability {
        enrollment.availability(hasKey: (try? store.data(for: Self.storeKey)) != nil)
    }

    /// Face ID first, on a context the key then uses, so there is exactly one prompt.
    public func sign(_ message: Data, reason: String) async throws(SigningError) -> Data {
        switch availability() {
        case .ready:
            break
        case .biometryNotSetUp:
            throw .biometryNotSetUp
        case .keyInvalidated:
            throw .keyInvalidated
        }
        guard let handle = try? store.data(for: Self.storeKey) else {
            throw .biometryNotSetUp
        }
        let context = LAContext()
        context.localizedFallbackTitle = ""
        do {
            _ = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch let error as LAError {
            throw Self.signingError(for: error.code)
        } catch {
            throw .failed
        }
        guard enrollment.matches(context.evaluatedPolicyDomainState) else {
            throw .keyInvalidated
        }
        do {
            let key = try SecureEnclave.P256.Signing.PrivateKey(
                dataRepresentation: handle,
                authenticationContext: context
            )
            return try key.signature(for: message).derRepresentation
        } catch {
            // The prompt passed but the key refused: the enrolment changed underneath it.
            throw .keyInvalidated
        }
    }

    public func remove() {
        try? store.remove(Self.storeKey)
        enrollment.remove()
    }

    static func signingError(for code: LAError.Code) -> SigningError {
        switch code {
        case .userCancel, .appCancel, .systemCancel, .userFallback:
            .cancelled
        case .biometryNotEnrolled:
            .keyInvalidated
        default:
            .failed
        }
    }
}
