import CryptoKit
import Domain
import Foundation

/// Binds this device after the password is checked (SPEC section 6): makes the signing key if
/// Face ID or Touch ID is set up, attests the app if App Attest is available, and exchanges
/// the binding token for a session tied to both.
struct DeviceBinder: Sendable {
    let api: any AuthAPI
    let key: any DeviceKey
    let attestor: any AppAttesting

    struct Bound {
        let session: BoundSession
        let record: DeviceRecord
    }

    /// No Face ID: bound without a key, so the device can view but not send. A key that
    /// can't be made although Face ID is set up is an error, not a quiet downgrade.
    func bind(_ token: BindingToken) async throws(AuthError) -> Bound {
        let signingKey: Data?
        if key.canMake() {
            do {
                signingKey = try key.make()
            } catch {
                throw .deviceSetupFailed
            }
        } else {
            signingKey = nil
        }
        var attestation: DeviceAttestation?
        if attestor.isSupported() {
            let clientData = DeviceBindingRequest.clientData(bindingToken: token, signingKey: signingKey)
            do {
                let keyID = try await attestor.generateKey()
                let object = try await attestor.attestKey(keyID, clientDataHash: Data(SHA256.hash(data: clientData)))
                attestation = DeviceAttestation(keyID: keyID, object: object)
            } catch {
                throw .deviceSetupFailed
            }
        }
        let session = try await api.bindDevice(
            DeviceBindingRequest(bindingToken: token, signingKey: signingKey, attestation: attestation)
        )
        return Bound(
            session: session, record: DeviceRecord(deviceID: session.deviceID, attestKeyID: attestation?.keyID))
    }
}
