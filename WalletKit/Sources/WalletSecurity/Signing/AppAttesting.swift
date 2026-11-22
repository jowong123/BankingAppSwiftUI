import DeviceCheck
import Foundation

/// App Attest: proves to the server that requests come from a genuine copy of this app on a
/// real device (SPEC section 6, ADR-024). `DeviceAppAttest` is the real one.
public protocol AppAttesting: Sendable {
    /// `false` on the simulator and on devices without a Secure Enclave.
    func isSupported() -> Bool
    func generateKey() async throws -> String
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data
}

/// `DCAppAttestService`. Needs the App Attest capability in the app's entitlements. Its
/// `shared` instance is Apple's API, not a singleton of ours; it is only reached through
/// this injected type.
public struct DeviceAppAttest: AppAttesting {
    public init() {}

    public func isSupported() -> Bool {
        DCAppAttestService.shared.isSupported
    }

    public func generateKey() async throws -> String {
        try await DCAppAttestService.shared.generateKey()
    }

    public func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.attestKey(keyID, clientDataHash: clientDataHash)
    }

    public func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: clientDataHash)
    }
}
