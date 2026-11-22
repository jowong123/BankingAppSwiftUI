import CryptoKit
import Domain
import Foundation

/// Approves transfers: the canonical payload, signed by the device key behind Face ID, plus
/// an App Attest assertion over the same bytes when this device was attested.
public struct TransferSigner: TransferSigning {
    private let key: any DeviceKey
    private let attestor: any AppAttesting
    private let store: any SecureStore

    public init(key: any DeviceKey, attestor: any AppAttesting, store: any SecureStore) {
        self.key = key
        self.attestor = attestor
        self.store = store
    }

    public func availability() async -> SigningAvailability {
        key.availability()
    }

    public func sign(_ payload: ConfirmPayload, reason: String) async throws(SigningError) -> SignedConfirmation {
        let bytes: Data
        do {
            bytes = try CanonicalPayload.encode(payload)
        } catch {
            throw .failed
        }
        let signature = try await key.sign(bytes, reason: reason)
        var assertion: Data?
        if let keyID = DeviceRecord.load(from: store)?.attestKeyID {
            do {
                assertion = try await attestor.generateAssertion(
                    keyID, clientDataHash: Data(SHA256.hash(data: bytes)))
            } catch {
                throw .failed
            }
        }
        return SignedConfirmation(payload: bytes, signature: signature, assertion: assertion)
    }
}

/// The bound device, kept in the Keychain with the session.
struct DeviceRecord: Codable, Equatable {
    let deviceID: String
    /// `nil` when App Attest wasn't available at binding (the simulator).
    let attestKeyID: String?

    static let storeKey = "session.device"

    static func load(from store: any SecureStore) -> DeviceRecord? {
        guard let data = try? store.data(for: storeKey) else {
            return nil
        }
        return try? JSONDecoder().decode(DeviceRecord.self, from: data)
    }
}
