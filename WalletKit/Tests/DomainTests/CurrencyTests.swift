import Testing

@testable import Domain

@Suite struct CurrencyTests {
    @Test func knownCurrenciesHaveISOMinorUnits() {
        #expect(Currency.jpy.minorUnits == 0)
        #expect(Currency.sgd.minorUnits == 2)
        #expect(Currency.usd.minorUnits == 2)
        #expect(Currency.eur.minorUnits == 2)
        #expect(Currency.kwd.minorUnits == 3)
    }

    @Test func validCodeIsAccepted() throws {
        let currency = try Currency(code: "CHF", minorUnits: 2)
        #expect(currency.code == "CHF")
        #expect(currency.minorUnits == 2)
    }

    @Test(arguments: [
        ("SG", 2),
        ("SGDX", 2),
        ("sgd", 2),
        ("S1D", 2),
        ("ÉUR", 2),
        ("SGD", -1),
        ("SGD", 5),
    ])
    func invalidCurrencyIsRejected(code: String, minorUnits: Int) {
        #expect(throws: MoneyError.invalidCurrency(code: code, minorUnits: minorUnits)) {
            try Currency(code: code, minorUnits: minorUnits)
        }
    }

    @Test func minorUnitsArePartOfIdentity() throws {
        // A server-sent "SGD with 3 decimals" must not silently mix with `.sgd`.
        #expect(try Currency(code: "SGD", minorUnits: 3) != .sgd)
        #expect(try Currency(code: "SGD", minorUnits: 2) == .sgd)
    }

    @Test func supportedLookupFindsKnownCodes() {
        #expect(Currency.supported(code: "JPY") == .jpy)
        #expect(Currency.supported(code: "KWD") == .kwd)
        #expect(Currency.supported(code: "SGD") == .sgd)
    }

    @Test(arguments: ["CHF", "sgd", "", "SGDX"])
    func supportedLookupRejectsUnknownCodes(code: String) {
        #expect(Currency.supported(code: code) == nil)
    }
}
