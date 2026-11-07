import Foundation
import Testing

@testable import Domain

/// The app's currency table must match the one the backend uses (`contracts/currencies.json`).
@Suite struct CurrencyContractTests {
    @Test func supportedCurrenciesMatchTheSharedContract() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "../../../contracts/currencies.json")
            .standardized
        let contract = try JSONDecoder().decode([String: Int].self, from: Data(contentsOf: url))

        let app = Dictionary(
            uniqueKeysWithValues: Currency.supported.map {
                ($0.code, $0.minorUnits)
            })

        #expect(app == contract)
    }
}
