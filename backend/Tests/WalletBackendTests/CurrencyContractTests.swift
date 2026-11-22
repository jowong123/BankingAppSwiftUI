import Foundation
import XCTest

@testable import WalletBackend

/// The backend's currency table and API contract must match the app's (`contracts/currencies.json`).
final class CurrencyContractTests: XCTestCase {
    private let repoRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "../../..")
        .standardized

    private func contract() throws -> [String: Int] {
        let data = try Data(contentsOf: repoRoot.appending(path: "contracts/currencies.json"))
        return try JSONDecoder().decode([String: Int].self, from: data)
    }

    func testMinorUnitsMatchTheSharedContract() throws {
        XCTAssertEqual(Currencies.minorUnits, try contract())
    }

    /// `openapi.yaml` is the API's source of truth; its `Money.currency` enum lists the same codes.
    func testOpenAPICurrencyEnumMatchesTheSharedContract() throws {
        let yaml = try String(contentsOf: repoRoot.appending(path: "backend/openapi.yaml"), encoding: .utf8)
        let match = try XCTUnwrap(yaml.firstMatch(of: /currency:\s*\n\s*type: string\s*\n\s*enum: \[([A-Z, ]+)\]/))
        let codes = match.output.1.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }

        XCTAssertEqual(Set(codes), Set(try contract().keys))
    }
}
