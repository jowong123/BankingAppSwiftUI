import Foundation
import Testing

@testable import WalletSecurity

@Suite struct PINHasherTests {
    /// RFC 7914 section 11: PBKDF2-HMAC-SHA256, P = "passwd", S = "salt", c = 1 (first 32 bytes).
    @Test func matchesThePublishedTestVector() throws {
        let derived = try PINHasher(iterations: 1).hash("passwd", salt: Data("salt".utf8), iterations: 1)

        #expect(
            derived.map { String(format: "%02x", $0) }.joined()
                == "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc")
    }

    @Test func verifiesTheRightPINOnly() throws {
        let record = try fastHasher.makeRecord(for: "123456")

        #expect(try fastHasher.verify("123456", against: record))
        #expect(try !fastHasher.verify("123457", against: record))
        #expect(try !fastHasher.verify("", against: record))
    }

    @Test func samePINGetsADifferentSaltAndHashEachTime() throws {
        let first = try fastHasher.makeRecord(for: "123456")
        let second = try fastHasher.makeRecord(for: "123456")

        #expect(first.salt.count == 16)
        #expect(first.salt != second.salt)
        #expect(first.hash != second.hash)
    }

    @Test func recordNeverContainsThePIN() throws {
        let record = try fastHasher.makeRecord(for: "123456")
        let encoded = try JSONEncoder().encode(record)

        #expect(!(String(bytes: encoded, encoding: .utf8) ?? "").contains("123456"))
    }

    @Test func productionUsesOWASPIterationCount() {
        #expect(PINHasher().iterations == 600_000)
    }
}
