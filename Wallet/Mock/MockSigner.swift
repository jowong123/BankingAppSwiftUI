#if DEBUG
    import Domain
    import Foundation
    import WalletSecurity

    /// Approves every transfer at once for `-mockServer`: UI tests can't answer a Face ID
    /// prompt. `-signing keyInvalidated|biometryNotSetUp` makes the device unable to sign, to
    /// show the explanation screen. Debug only; the real signer is `TransferSigner`.
    struct MockSigner: TransferSigning {
        let availability: SigningAvailability

        func availability() async -> SigningAvailability {
            availability
        }

        func sign(_ payload: ConfirmPayload, reason: String) async throws(SigningError) -> SignedConfirmation {
            switch availability {
            case .ready:
                SignedConfirmation(payload: Data("mock".utf8), signature: Data("mock".utf8), assertion: nil)
            case .keyInvalidated:
                throw .keyInvalidated
            case .biometryNotSetUp:
                throw .biometryNotSetUp
            }
        }

        /// The mock session binds without App Attest, like the simulator.
        struct NoAppAttest: AppAttesting {
            func isSupported() -> Bool {
                false
            }

            func generateKey() async throws -> String {
                throw CancellationError()
            }

            func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
                throw CancellationError()
            }

            func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
                throw CancellationError()
            }
        }
    }
#endif
