import Crypto
import XCTest

@testable import WalletBackend

final class AppAttestVerifierTests: XCTestCase {
    let clientData = Data("binding-token.signing-key".utf8)

    func testValidAttestationReturnsTheKey() async throws {
        let attest = try FakeAppAttest()
        let key = FakeAppAttest.Key()

        let attested = try await attest.verifier().verifyAttestation(
            try attest.attestation(for: key, clientData: clientData),
            keyID: key.keyID,
            clientData: clientData
        )

        XCTAssertEqual(attested.publicKey, key.privateKey.publicKey.x963Representation)
        XCTAssertEqual(attested.counter, 0)
    }

    /// Each case breaks one rule from Apple's list; each must be refused.
    func testEveryBrokenRuleIsRefused() async throws {
        let attest = try FakeAppAttest()
        let key = FakeAppAttest.Key()
        let otherRoot = try FakeAppAttest()
        struct Case {
            let name: String
            let object: Data
            let verifier: AppAttestVerifier

            init(_ name: String, _ object: Data, _ verifier: AppAttestVerifier) {
                self.name = name
                self.object = object
                self.verifier = verifier
            }
        }
        let cases: [Case] = [
            Case("untrusted root", try otherRoot.attestation(for: key, clientData: clientData), attest.verifier()),
            Case(
                "other client data",
                try attest.attestation(for: key, clientData: clientData, certifiedClientData: Data("x".utf8)),
                attest.verifier()
            ),
            Case(
                "other app", try attest.attestation(for: key, clientData: clientData, appID: "OTHER.app"),
                attest.verifier()
            ),
            Case(
                "counter not zero", try attest.attestation(for: key, clientData: clientData, counter: 1),
                attest.verifier()
            ),
            Case(
                "development key in production",
                try attest.attestation(for: key, clientData: clientData),
                attest.verifier(allowsDevelopment: false)
            ),
            Case("not CBOR", Data("nonsense".utf8), attest.verifier()),
        ]
        for item in cases {
            do {
                _ = try await item.verifier.verifyAttestation(item.object, keyID: key.keyID, clientData: clientData)
                XCTFail("\(item.name) was accepted")
            } catch {}
        }
    }

    func testKeyIDMustMatchTheCertifiedKey() async throws {
        let attest = try FakeAppAttest()
        let key = FakeAppAttest.Key()

        do {
            _ = try await attest.verifier().verifyAttestation(
                try attest.attestation(for: key, clientData: clientData),
                keyID: FakeAppAttest.Key().keyID,
                clientData: clientData
            )
            XCTFail("another key ID was accepted")
        } catch {}
    }

    func testProductionKeyIsAcceptedWithoutDevelopment() async throws {
        let attest = try FakeAppAttest()
        let key = FakeAppAttest.Key()

        _ = try await attest.verifier(allowsDevelopment: false).verifyAttestation(
            try attest.attestation(for: key, clientData: clientData, aaguid: AppAttestVerifier.productionAAGUID),
            keyID: key.keyID,
            clientData: clientData
        )
    }

    func testAssertionCounterMustGoUp() throws {
        let attest = try FakeAppAttest()
        let key = FakeAppAttest.Key()
        let publicKey = key.privateKey.publicKey.x963Representation
        let assertion = try attest.assertion(for: key, clientData: clientData, counter: 1)

        let counter = try attest.verifier().verifyAssertion(
            assertion, clientData: clientData, publicKey: publicKey, previousCounter: 0)

        XCTAssertEqual(counter, 1)
        XCTAssertThrowsError(
            try attest.verifier().verifyAssertion(
                assertion, clientData: clientData, publicKey: publicKey, previousCounter: 1)
        )
    }

    func testAssertionOverOtherDataOrFromAnotherKeyIsRefused() throws {
        let attest = try FakeAppAttest()
        let key = FakeAppAttest.Key()
        let assertion = try attest.assertion(for: key, clientData: clientData, counter: 1)

        XCTAssertThrowsError(
            try attest.verifier().verifyAssertion(
                assertion,
                clientData: Data("tampered".utf8),
                publicKey: key.privateKey.publicKey.x963Representation,
                previousCounter: 0
            )
        )
        XCTAssertThrowsError(
            try attest.verifier().verifyAssertion(
                assertion,
                clientData: clientData,
                publicKey: FakeAppAttest.Key().privateKey.publicKey.x963Representation,
                previousCounter: 0
            )
        )
    }

    /// The real root parses and is Apple's.
    func testAppleRootLoads() throws {
        let root = try AppAttestVerifier.appleRoot()
        XCTAssertTrue(root.subject.description.contains("Apple App Attestation Root CA"))
    }
}

final class CBORTests: XCTestCase {
    func testDecodesTheShapesAppAttestUses() throws {
        let value = CBOR.map([
            "fmt": .text("apple-appattest"),
            "list": .array([.bytes(Data([1, 2, 3])), .unsigned(500), .negative(0)]),
            "flag": .bool(true),
        ])

        XCTAssertEqual(try CBOR.decode(TestCBOR.encode(value)), value)
    }

    func testRefusesMalformedInput() {
        let cases: [Data] = [
            TestCBOR.encode(.text("a")) + Data([0x00]),  // trailing byte
            Data([0x5F]),  // indefinite-length bytes
            Data([0x5A, 0xFF, 0xFF, 0xFF, 0xFF]),  // length beyond the data
            Data(repeating: 0x81, count: 20) + Data([0x00]),  // nested too deeply
            Data([0xA1, 0x01, 0x01]),  // map key that isn't text
            Data([0xF9, 0x3C, 0x00]),  // a float
        ]
        for data in cases {
            XCTAssertThrowsError(try CBOR.decode(data), "\(data as NSData)")
        }
    }
}
