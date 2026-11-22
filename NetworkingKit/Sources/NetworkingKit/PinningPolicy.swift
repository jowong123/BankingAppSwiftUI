import Foundation

/// TLS public-key pinning (ADR-006). A pinned host must present a certificate chain that the
/// system trusts *and* that contains a key whose SubjectPublicKeyInfo hash is one of the pins.
/// Pinning the key rather than the certificate lets the server renew its certificate on the
/// same key; the backup pin lets it move to a new key without shipping an app update first.
///
/// Foundation only (ADR-012), so the caller supplies SHA-256.
public struct PinningPolicy: Sendable {
    /// Lowercased host → SHA-256 hashes of SubjectPublicKeyInfo DER.
    public let pins: [String: Set<Data>]
    private let sha256: @Sendable (Data) -> Data

    public init(pins: [String: Set<Data>], sha256: @escaping @Sendable (Data) -> Data) {
        self.pins = Dictionary(
            pins.map {
                ($0.key.lowercased(), $0.value)
            },
            uniquingKeysWith: {
                $0.union($1)
            }
        )
        self.sha256 = sha256
    }

    public enum Verdict: Equatable, Sendable {
        /// The host isn't pinned: the system's normal checks apply.
        case notPinned
        case trusted
        case rejected
    }

    /// A pinned host with an empty pin set fails closed.
    public func evaluate(_ trust: SecTrust, host: String) -> Verdict {
        guard let expected = pins[host.lowercased()] else {
            return .notPinned
        }
        guard !expected.isEmpty, SecTrustEvaluateWithError(trust, nil),
            let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate]
        else {
            return .rejected
        }
        let matches = chain.contains { certificate in
            spkiHash(of: certificate).map(expected.contains) ?? false
        }
        return matches ? .trusted : .rejected
    }

    /// SHA-256 of the certificate's SubjectPublicKeyInfo: the same value as
    /// `openssl x509 -pubkey | openssl pkey -pubin -outform der | openssl dgst -sha256`.
    public func spkiHash(of certificate: SecCertificate) -> Data? {
        guard let key = SecCertificateCopyKey(certificate),
            let attributes = SecKeyCopyAttributes(key) as? [CFString: Any],
            let type = attributes[kSecAttrKeyType] as? String,
            let bits = attributes[kSecAttrKeySizeInBits] as? Int,
            let header = Self.spkiHeader(keyType: type, bits: bits),
            let raw = SecKeyCopyExternalRepresentation(key, nil) as Data?
        else {
            return nil
        }
        return sha256(header + raw)
    }

    /// `SecKeyCopyExternalRepresentation` returns the bare key; SPKI wraps it in an ASN.1
    /// header naming the algorithm. These are the fixed headers for the key types servers use.
    static func spkiHeader(keyType: String, bits: Int) -> Data? {
        let isEC = keyType == kSecAttrKeyTypeECSECPrimeRandom as String
        let isRSA = keyType == kSecAttrKeyTypeRSA as String
        return switch (isEC, isRSA, bits) {
        case (true, _, 256):
            Data([
                0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01, 0x06, 0x08, 0x2A,
                0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
            ])
        case (true, _, 384):
            Data([
                0x30, 0x76, 0x30, 0x10, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01, 0x06, 0x05, 0x2B,
                0x81, 0x04, 0x00, 0x22, 0x03, 0x62, 0x00,
            ])
        case (_, true, 2048):
            Data([
                0x30, 0x82, 0x01, 0x22, 0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01,
                0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0F, 0x00,
            ])
        case (_, true, 4096):
            Data([
                0x30, 0x82, 0x02, 0x22, 0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01,
                0x01, 0x05, 0x00, 0x03, 0x82, 0x02, 0x0F, 0x00,
            ])
        default:
            nil
        }
    }
}
