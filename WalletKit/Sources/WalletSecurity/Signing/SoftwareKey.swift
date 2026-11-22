#if targetEnvironment(simulator) || DEBUG
    import CryptoKit
    import Domain
    import Foundation

    /// The simulator's stand-in for `SecureEnclaveKey` (ADR-023). Same interface and same rules:
    /// made at sign-in, signs only after a Face ID prompt (the simulator's Features > Face ID
    /// menu answers it), and stops working when the enrolment changes.
    ///
    /// The difference: the private key is generated on the device and kept in the Keychain
    /// (`WhenUnlockedThisDeviceOnly`), not in a Secure Enclave. `AppEnvironment` uses it only in
    /// simulator builds (and the Debug mock); on a phone the Secure Enclave key is always used.
    /// Never a fixed key. Not compiled into Release device builds at all.
    public struct SoftwareKey: DeviceKey {
        private let store: any SecureStore
        private let enrollment: KeyEnrollment

        static let storeKey = "device.softwareKey"

        public init(store: any SecureStore, biometrics: any BiometricAuthenticator) {
            self.store = store
            enrollment = KeyEnrollment(store: store, biometrics: biometrics)
        }

        public func canMake() -> Bool {
            enrollment.biometrics.enrollmentState() != nil
        }

        public func make() throws(SigningError) -> Data {
            remove()
            guard canMake() else {
                throw .biometryNotSetUp
            }
            let key = P256.Signing.PrivateKey()
            do {
                try store.set(key.rawRepresentation, for: Self.storeKey)
            } catch {
                throw .failed
            }
            do {
                try enrollment.save()
            } catch {
                remove()
                throw error
            }
            return key.publicKey.x963Representation
        }

        public func availability() -> SigningAvailability {
            enrollment.availability(hasKey: (try? store.data(for: Self.storeKey)) != nil)
        }

        public func sign(_ message: Data, reason: String) async throws(SigningError) -> Data {
            switch availability() {
            case .ready:
                break
            case .biometryNotSetUp:
                throw .biometryNotSetUp
            case .keyInvalidated:
                throw .keyInvalidated
            }
            let authenticated: Data?
            do {
                authenticated = try await enrollment.biometrics.authenticate(reason: reason)
            } catch .cancelled {
                throw .cancelled
            } catch {
                throw .failed
            }
            guard enrollment.matches(authenticated) else {
                throw .keyInvalidated
            }
            guard let raw = try? store.data(for: Self.storeKey),
                let key = try? P256.Signing.PrivateKey(rawRepresentation: raw),
                let signature = try? key.signature(for: message)
            else {
                throw .failed
            }
            return signature.derRepresentation
        }

        public func remove() {
            try? store.remove(Self.storeKey)
            enrollment.remove()
        }
    }
#endif
