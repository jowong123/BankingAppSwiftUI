import Foundation

/// What the app sends to bind this device (`POST /v1/devices`, SPEC section 6).
public struct DeviceBindingRequest: Hashable, Sendable {
    public let bindingToken: BindingToken
    /// X9.63 P-256 public key of the Secure Enclave signing key. `nil` when the phone has no
    /// Face ID or Touch ID set up: the device can then view but not send.
    public let signingKey: Data?
    /// `nil` where App Attest isn't available (the simulator).
    public let attestation: DeviceAttestation?

    public init(bindingToken: BindingToken, signingKey: Data?, attestation: DeviceAttestation?) {
        self.bindingToken = bindingToken
        self.signingKey = signingKey
        self.attestation = attestation
    }

    /// The App Attest client data: the binding token and the signing key, so the attestation
    /// vouches for this key and can't be reused with another. The server builds the same bytes.
    public static func clientData(bindingToken: BindingToken, signingKey: Data?) -> Data {
        Data("\(bindingToken.value).\(signingKey?.base64EncodedString() ?? "")".utf8)
    }
}

public struct DeviceAttestation: Hashable, Sendable {
    /// The App Attest key's identifier, base64, as `DCAppAttestService` returns it.
    public let keyID: String
    /// The CBOR attestation object.
    public let object: Data

    public init(keyID: String, object: Data) {
        self.keyID = keyID
        self.object = object
    }
}

/// The session the server starts once the device is bound.
public struct BoundSession: Hashable, Sendable {
    public let deviceID: String
    public let tokens: SessionTokens

    public init(deviceID: String, tokens: SessionTokens) {
        self.deviceID = deviceID
        self.tokens = tokens
    }
}
