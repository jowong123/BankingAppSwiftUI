import Crypto
import Foundation
import SwiftASN1
import X509

/// Checks App Attest objects the way Apple describes in "Validating apps that connect to
/// your server" (ADR-024). The attestation proves a key lives in a genuine copy of this app
/// on a real Apple device; each later assertion proves a request came from that key.
struct AppAttestVerifier: Sendable {
    /// "<Team ID>.<bundle ID>". Its SHA-256 is the `rpIdHash` in every authenticator data.
    let appID: String
    /// Apple's App Attestation root in production; a test root in tests.
    let roots: [Certificate]
    /// Accept keys from the development App Attest environment (debug builds).
    let allowsDevelopment: Bool

    struct Failure: Error, Equatable {
        let reason: String
    }

    /// The attested key to store with the device.
    struct AttestedKey: Equatable, Sendable {
        /// X9.63 uncompressed P-256 point.
        let publicKey: Data
        let counter: UInt32
    }

    /// - Parameters:
    ///   - object: the attestation object (CBOR) from `DCAppAttestService.attestKey`.
    ///   - keyID: the key identifier the app sent, decoded from base64.
    ///   - clientData: the bytes whose SHA-256 the app passed as `clientDataHash`.
    func verifyAttestation(_ object: Data, keyID: Data, clientData: Data) async throws -> AttestedKey {
        let cbor = try decode(object)
        guard cbor["fmt"]?.textValue == "apple-appattest",
            let statement = cbor["attStmt"],
            let chain = statement["x5c"]?.arrayValue?.compactMap(\.bytesValue), !chain.isEmpty,
            let authData = cbor["authData"]?.bytesValue
        else {
            throw Failure(reason: "not an App Attest object")
        }

        // 1. The certificate chain ends at the trusted root, and is valid now (the real clock:
        // Apple's leaf certificates last a few days).
        let certificates = try chain.map {
            try Certificate(derEncoded: [UInt8]($0))
        }
        var verifier = Verifier(rootCertificates: CertificateStore(roots)) {
            RFC5280Policy()
        }
        let result = await verifier.validate(
            leaf: certificates[0],
            intermediates: CertificateStore(certificates.dropFirst())
        )
        guard case .validCertificate = result else {
            throw Failure(reason: "certificate chain not trusted")
        }

        // 2. The leaf certifies this exact authenticator data and client data.
        let nonce = Data(SHA256.hash(data: authData + Data(SHA256.hash(data: clientData))))
        guard let nonceExtension = certificates[0].extensions[oid: Self.nonceOID],
            Data(nonceExtension.value) == Self.nonceExtensionPrefix + nonce
        else {
            throw Failure(reason: "nonce mismatch")
        }

        // 3. The key ID is the hash of the leaf's public key.
        guard let leafKey = P256.Signing.PublicKey(certificates[0].publicKey) else {
            throw Failure(reason: "leaf key is not P-256")
        }
        let publicKey = leafKey.x963Representation
        guard Data(SHA256.hash(data: publicKey)) == keyID else {
            throw Failure(reason: "key ID mismatch")
        }

        // 4. The authenticator data is for this app, a new key, and the expected environment.
        let parsed = try AuthenticatorData(authData)
        try checkAppID(parsed)
        guard parsed.counter == 0 else {
            throw Failure(reason: "counter must start at 0")
        }
        guard parsed.aaguid == Self.productionAAGUID || (allowsDevelopment && parsed.aaguid == Self.developmentAAGUID)
        else {
            throw Failure(reason: "wrong App Attest environment")
        }
        guard parsed.credentialID == keyID else {
            throw Failure(reason: "credential ID mismatch")
        }
        return AttestedKey(publicKey: publicKey, counter: 0)
    }

    /// Checks one assertion and returns its counter, which must be higher than the last one
    /// seen for this key: a replayed assertion has an old counter.
    func verifyAssertion(_ object: Data, clientData: Data, publicKey: Data, previousCounter: UInt32) throws
        -> UInt32
    {
        let cbor = try decode(object)
        guard let signatureData = cbor["signature"]?.bytesValue,
            let authData = cbor["authenticatorData"]?.bytesValue
        else {
            throw Failure(reason: "not an assertion")
        }
        let nonce = Data(SHA256.hash(data: authData + Data(SHA256.hash(data: clientData))))
        guard let key = try? P256.Signing.PublicKey(x963Representation: publicKey),
            let signature = try? P256.Signing.ECDSASignature(derRepresentation: signatureData),
            key.isValidSignature(signature, for: nonce)
        else {
            throw Failure(reason: "assertion signature invalid")
        }
        let parsed = try AuthenticatorData(authData)
        try checkAppID(parsed)
        guard parsed.counter > previousCounter else {
            throw Failure(reason: "counter did not increase")
        }
        return parsed.counter
    }

    private func checkAppID(_ data: AuthenticatorData) throws {
        guard data.rpIDHash == Data(SHA256.hash(data: Data(appID.utf8))) else {
            throw Failure(reason: "wrong app ID")
        }
    }

    private func decode(_ object: Data) throws -> CBOR {
        do {
            return try CBOR.decode(object)
        } catch {
            throw Failure(reason: "invalid CBOR")
        }
    }

    /// Apple's extension holding the nonce in the leaf certificate.
    static let nonceOID: ASN1ObjectIdentifier = [1, 2, 840, 113_635, 100, 8, 2]
    /// The extension's DER: SEQUENCE { [1] { OCTET STRING (32 bytes) } }, then the nonce.
    static let nonceExtensionPrefix = Data([0x30, 0x24, 0xA1, 0x22, 0x04, 0x20])
    static let productionAAGUID = Data("appattest".utf8) + Data(repeating: 0, count: 7)
    static let developmentAAGUID = Data("appattestdevelop".utf8)
}

/// The authenticator data layout shared by attestations and assertions (WebAuthn).
struct AuthenticatorData: Equatable {
    let rpIDHash: Data
    let counter: UInt32
    /// Only in an attestation.
    let aaguid: Data?
    let credentialID: Data?

    init(_ data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count >= 37 else {
            throw AppAttestVerifier.Failure(reason: "authenticator data too short")
        }
        rpIDHash = Data(bytes[0..<32])
        counter = bytes[33..<37].reduce(0) {
            $0 << 8 | UInt32($1)
        }
        let hasCredential = bytes[32] & 0x40 != 0
        guard hasCredential else {
            aaguid = nil
            credentialID = nil
            return
        }
        guard bytes.count >= 55 else {
            throw AppAttestVerifier.Failure(reason: "credential data too short")
        }
        aaguid = Data(bytes[37..<53])
        let length = Int(bytes[53]) << 8 | Int(bytes[54])
        guard bytes.count >= 55 + length else {
            throw AppAttestVerifier.Failure(reason: "credential ID too short")
        }
        credentialID = Data(bytes[55..<55 + length])
    }
}

extension AppAttestVerifier {
    /// Apple App Attestation Root CA, from
    /// https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem
    /// (SHA-256 fingerprint 1C:B9:82:3B:A2:8B:A6:AD:2D:33:A0:06:94:1D:E2:AE:4F:51:3E:F1:D4:E8:31:B9:F7:E0:FA:7B:62:42:C9:32).
    /// A public certificate, not a secret.
    static let appleRootPEM = """
        -----BEGIN CERTIFICATE-----
        MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
        JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
        QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
        Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
        biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
        bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
        NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
        Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
        MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
        CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
        53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijV
        oyFraWVIyd/dganmrduC1bmTBGwD
        -----END CERTIFICATE-----
        """

    static func appleRoot() throws -> Certificate {
        try Certificate(pemEncoded: appleRootPEM)
    }
}
