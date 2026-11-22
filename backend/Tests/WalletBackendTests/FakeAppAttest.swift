import Crypto
import Foundation
import X509

@testable import WalletBackend

/// Makes App Attest objects the way a device does, signed by a test root instead of Apple's,
/// so the verifier's every check can be exercised without a phone.
struct FakeAppAttest {
    static let appID = "TEAM123456.jw.Wallet"

    let rootKey = P256.Signing.PrivateKey()
    let root: Certificate

    init() throws {
        let name = try DistinguishedName {
            CommonName("Test App Attestation Root")
        }
        root = try Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: .init(rootKey.publicKey),
            notValidBefore: Date().addingTimeInterval(-3600),
            notValidAfter: Date().addingTimeInterval(86_400),
            issuer: name,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil))
                KeyUsage(keyCertSign: true)
            },
            issuerPrivateKey: .init(rootKey)
        )
    }

    func verifier(allowsDevelopment: Bool = true) -> AppAttestVerifier {
        AppAttestVerifier(appID: Self.appID, roots: [root], allowsDevelopment: allowsDevelopment)
    }

    /// The device's App Attest key.
    struct Key {
        let privateKey = P256.Signing.PrivateKey()

        var keyID: Data {
            Data(SHA256.hash(data: privateKey.publicKey.x963Representation))
        }
    }

    /// An attestation object for `key` over `clientData`. The parameters break one check each.
    func attestation(
        for key: Key,
        clientData: Data,
        appID: String = appID,
        aaguid: Data = AppAttestVerifier.developmentAAGUID,
        counter: UInt32 = 0,
        certifiedClientData: Data? = nil,
        signer: P256.Signing.PrivateKey? = nil
    ) throws -> Data {
        var authData = Self.rpIDHash(appID)
        authData.append(0x41)
        authData.append(contentsOf: Self.bigEndian(counter))
        authData.append(aaguid)
        authData.append(contentsOf: [UInt8(key.keyID.count >> 8), UInt8(key.keyID.count & 0xFF)])
        authData.append(key.keyID)
        let nonce = Data(
            SHA256.hash(data: authData + Data(SHA256.hash(data: certifiedClientData ?? clientData))))
        let leaf = try Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: .init(key.privateKey.publicKey),
            notValidBefore: Date().addingTimeInterval(-60),
            notValidAfter: Date().addingTimeInterval(3600),
            issuer: root.subject,
            subject: try DistinguishedName {
                CommonName("Test credential")
            },
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try Certificate.Extensions {
                Certificate.Extension(
                    oid: AppAttestVerifier.nonceOID,
                    critical: false,
                    value: ArraySlice(AppAttestVerifier.nonceExtensionPrefix + nonce)
                )
            },
            issuerPrivateKey: .init(signer ?? rootKey)
        )
        return TestCBOR.encode(
            .map([
                "fmt": .text("apple-appattest"),
                "attStmt": .map([
                    "x5c": .array([.bytes(Data(try leaf.serializeAsPEM().derBytes))]),
                    "receipt": .bytes(Data()),
                ]),
                "authData": .bytes(authData),
            ]))
    }

    func assertion(for key: Key, clientData: Data, counter: UInt32, appID: String = appID) throws -> Data {
        var authData = Self.rpIDHash(appID)
        authData.append(0x01)
        authData.append(contentsOf: Self.bigEndian(counter))
        let nonce = Data(SHA256.hash(data: authData + Data(SHA256.hash(data: clientData))))
        let signature = try key.privateKey.signature(for: nonce)
        return TestCBOR.encode(
            .map([
                "signature": .bytes(signature.derRepresentation),
                "authenticatorData": .bytes(authData),
            ]))
    }

    private static func rpIDHash(_ appID: String) -> Data {
        Data(SHA256.hash(data: Data(appID.utf8)))
    }

    private static func bigEndian(_ value: UInt32) -> [UInt8] {
        [24, 16, 8, 0].map {
            UInt8(truncatingIfNeeded: value >> $0)
        }
    }
}

/// A CBOR encoder for test fixtures; the server only decodes.
enum TestCBOR {
    static func encode(_ value: CBOR) -> Data {
        switch value {
        case .unsigned(let number):
            return head(0, number)
        case .negative(let number):
            return head(1, number)
        case .bytes(let data):
            return head(2, UInt64(data.count)) + data
        case .text(let text):
            return head(3, UInt64(text.utf8.count)) + Data(text.utf8)
        case .array(let items):
            return items.reduce(head(4, UInt64(items.count))) {
                $0 + encode($1)
            }
        case .map(let map):
            return map.keys.sorted().reduce(head(5, UInt64(map.count))) { data, key in
                data + encode(.text(key)) + encode(map[key] ?? .null)
            }
        case .bool(let flag):
            return Data([flag ? 0xF5 : 0xF4])
        case .null:
            return Data([0xF6])
        }
    }

    static func head(_ major: UInt8, _ value: UInt64) -> Data {
        let type = major << 5
        switch value {
        case 0..<24:
            return Data([type | UInt8(value)])
        case 24...0xFF:
            return Data([type | 24, UInt8(value)])
        case 0x100...0xFFFF:
            return Data([type | 25, UInt8(value >> 8), UInt8(value & 0xFF)])
        default:
            return Data(
                [type | 26]
                    + [24, 16, 8, 0].map {
                        UInt8(truncatingIfNeeded: value >> $0)
                    })
        }
    }
}
