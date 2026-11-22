import CryptoKit
import Foundation
import Testing

@testable import NetworkingKit

/// A test CA and a server certificate for `pinned.test`, made with openssl. The pins are what
/// `openssl x509 -pubkey | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64`
/// prints for each, so `spkiHash` is checked against an independent tool.
@Suite struct PinningPolicyTests {
    static let leafDER =
        "MIIBvzCCAWagAwIBAgIUVvRJ6Ms+V2cVT9f/q2MQh+1182wwCgYIKoZIzj0EAwIwHDEaMBgGA1UEAwwRUGlubmluZyBUZXN0IFJvb3QwHhcNMjYxMTE0MDkxODUwWhcNMjcxMjE2MDkxODUwWjAWMRQwEgYDVQQDDAtwaW5uZWQudGVzdDBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABD4NrxI60A8/E1KTThX4TeBIqXOErWH3fliPjm/oGW2gjlk5qgF4tTTE0rB3YmiaPzl+9o3mrKqNWKkdmLM8xBSjgYswgYgwFgYDVR0RBA8wDYILcGlubmVkLnRlc3QwEwYDVR0lBAwwCgYIKwYBBQUHAwEwCQYDVR0TBAIwADAOBgNVHQ8BAf8EBAMCB4AwHQYDVR0OBBYEFLzMf7oKI1ettNmeRONMOLdp4S5dMB8GA1UdIwQYMBaAFDaiV3eWL+x3PfHfNjESDVb0QzdUMAoGCCqGSM49BAMCA0cAMEQCIBOeBlEJjX2cVUO5o49CSM/3fdpF7HBHJ46B1GD3TGdkAiAdhxiAF7wC0IZYKHD44cvBu8Je0FIGY4h6vcf1whtNBQ=="
    static let caDER =
        "MIIBnjCCAUOgAwIBAgIUBweU743UU5+77vCuTRkOVDLcNXgwCgYIKoZIzj0EAwIwHDEaMBgGA1UEAwwRUGlubmluZyBUZXN0IFJvb3QwHhcNMjYxMTE0MDkxODUwWhcNMzYxMTExMDkxODUwWjAcMRowGAYDVQQDDBFQaW5uaW5nIFRlc3QgUm9vdDBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABCwxTahFvHHUmdp0BYKMMdfRFoVRoV6jqprjQi2phNKDdvZonks1MkJWoR8gEuyxnfliEc4CN7n4fA3oCbHT/2CjYzBhMB0GA1UdDgQWBBQ2old3li/sdz3x3zYxEg1W9EM3VDAfBgNVHSMEGDAWgBQ2old3li/sdz3x3zYxEg1W9EM3VDAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwICBDAKBggqhkjOPQQDAgNJADBGAiEAnrGWmOLZhBFrE39lFzqTzZBTVShTz9KubCjAjHmRbEMCIQCYvuTumUPk/WVIX107guxqLpebaxg6fjPKilQzn92Elg=="
    static let leafPin = "fnqWHGlkATz7Pz48l7QTMAf9U+RSLJzLSP1kFzR/uSw="
    static let caPin = "klS0KhjuoQqDnDaQ2u0L3dpvh+VaZneA6h8HpI3iLOo="
    /// Inside the leaf's validity (Nov 2026 to Dec 2027), so the test never expires.
    static let verifyDate = Date(timeIntervalSince1970: 1_798_761_600)

    @Test func spkiHashMatchesOpenSSL() throws {
        let policy = Self.policy(pins: [:])

        #expect(policy.spkiHash(of: try Self.certificate(Self.leafDER)) == Self.data(Self.leafPin))
        #expect(policy.spkiHash(of: try Self.certificate(Self.caDER)) == Self.data(Self.caPin))
    }

    @Test func pinnedLeafKeyPasses() throws {
        let policy = Self.policy(pins: ["pinned.test": [Self.data(Self.leafPin)]])

        #expect(policy.evaluate(try Self.trust(for: "pinned.test"), host: "Pinned.Test") == .trusted)
    }

    /// The backup pin can be any key in the chain, here the CA's.
    @Test func backupPinOnTheCAPasses() throws {
        let policy = Self.policy(pins: ["pinned.test": [Data(repeating: 1, count: 32), Self.data(Self.caPin)]])

        #expect(policy.evaluate(try Self.trust(for: "pinned.test"), host: "pinned.test") == .trusted)
    }

    /// A trusted certificate with another key: what a proxy with its own trusted CA presents.
    @Test func otherKeyFails() throws {
        let policy = Self.policy(pins: ["pinned.test": [Data(repeating: 1, count: 32)]])

        #expect(policy.evaluate(try Self.trust(for: "pinned.test"), host: "pinned.test") == .rejected)
    }

    /// Pinning adds to the system's checks, never replaces them: a certificate for another
    /// name fails even though its key is pinned.
    @Test func untrustedChainFailsEvenWithAPinnedKey() throws {
        let policy = Self.policy(pins: ["evil.test": [Self.data(Self.leafPin)]])

        #expect(policy.evaluate(try Self.trust(for: "evil.test"), host: "evil.test") == .rejected)
    }

    @Test func pinnedHostWithNoPinsFailsClosed() throws {
        let policy = Self.policy(pins: ["pinned.test": []])

        #expect(policy.evaluate(try Self.trust(for: "pinned.test"), host: "pinned.test") == .rejected)
    }

    @Test func unpinnedHostIsLeftToTheSystem() throws {
        let policy = Self.policy(pins: ["other.test": [Self.data(Self.leafPin)]])

        #expect(policy.evaluate(try Self.trust(for: "pinned.test"), host: "pinned.test") == .notPinned)
    }

    /// URLSession reports a rejected challenge as a cancel; the transport must not.
    @Test func pinningFailureIsNotReportedAsACancel() {
        let pinned = URLSessionTransport.error(for: .cancelled, pinningFailed: true)
        let cancelled = URLSessionTransport.error(for: .cancelled, pinningFailed: false)

        #expect(pinned as? HTTPError == .pinningFailed)
        #expect(cancelled is CancellationError)
    }

    // MARK: - Helpers

    static func policy(pins: [String: Set<Data>]) -> PinningPolicy {
        PinningPolicy(pins: pins) {
            Data(SHA256.hash(data: $0))
        }
    }

    static func data(_ base64: String) -> Data {
        Data(base64Encoded: base64) ?? Data()
    }

    static func certificate(_ base64: String) throws -> SecCertificate {
        try #require(SecCertificateCreateWithData(nil, data(base64) as CFData))
    }

    /// The chain a server for `host` would present, trusted only through the test CA.
    static func trust(for host: String) throws -> SecTrust {
        let leaf = try certificate(leafDER)
        let root = try certificate(caDER)
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(
            [leaf, root] as CFArray, SecPolicyCreateSSL(true, host as CFString), &trust)
        let created = try #require(trust)
        #expect(status == errSecSuccess)
        SecTrustSetAnchorCertificates(created, [root] as CFArray)
        SecTrustSetAnchorCertificatesOnly(created, true)
        SecTrustSetVerifyDate(created, verifyDate as CFDate)
        return created
    }
}
