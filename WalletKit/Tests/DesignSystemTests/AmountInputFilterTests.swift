import Domain
import Foundation
import Testing

@testable import DesignSystem

@Suite struct AmountInputFilterTests {
    let enUS = Locale(identifier: "en_US")
    let deDE = Locale(identifier: "de_DE")

    @Test(arguments: [
        ("", ""),
        ("12", "12"),
        ("12.50", "12.50"),
        ("12.505", "12.50"),  // Third decimal dropped (truncated while typing, not rounded).
        ("1.2.3", "1.23"),  // Only the first separator counts.
        ("007", "7"),
        ("00", "0"),
        ("0", "0"),
        (".", "0."),
        (".5", "0.5"),
        ("0.5", "0.5"),
        ("12.", "12."),  // Trailing separator kept so the user can keep typing.
        ("1,234.50", "1234.50"),  // Grouping separator dropped.
        ("$12.50", "12.50"),
        ("-12", "12"),  // No negative amounts.
        ("abc", ""),
        ("1 000", "1000"),
        ("９", "9"),  // Full-width digit from a Japanese keyboard.
        ("١٢٣", "123"),  // Arabic-Indic digits.
    ])
    func sanitizesSGDInEnglish(input: String, expected: String) {
        let filter = AmountInputFilter(currency: .sgd, locale: enUS)
        #expect(filter.sanitize(input) == expected)
    }

    @Test(arguments: [
        ("12,50", "12,50"),
        ("1.234,50", "1234,50"),  // German grouping dot dropped, comma is the decimal.
        (",5", "0,5"),
        ("12,505", "12,50"),
    ])
    func sanitizesInGerman(input: String, expected: String) {
        let filter = AmountInputFilter(currency: .eur, locale: deDE)
        #expect(filter.sanitize(input) == expected)
    }

    @Test(arguments: [
        ("1234", "1234"),
        ("1.5", "1"),  // Fraction is truncated, never joined into 15.
        ("1,234", "1234"),
        (".", "0"),
        ("12.", "12"),
    ])
    func jpyHasNoDecimals(input: String, expected: String) {
        let filter = AmountInputFilter(currency: .jpy, locale: enUS)
        #expect(filter.sanitize(input) == expected)
    }

    @Test(arguments: [
        ("1.234", "1.234"),
        ("1.2345", "1.234"),
        ("0.001", "0.001"),
    ])
    func kwdAllowsThreeDecimals(input: String, expected: String) {
        let filter = AmountInputFilter(currency: .kwd, locale: enUS)
        #expect(filter.sanitize(input) == expected)
    }

    @Test func capsIntegerDigits() {
        let filter = AmountInputFilter(currency: .sgd, locale: enUS)
        #expect(filter.sanitize(String(repeating: "9", count: 15)) == String(repeating: "9", count: 12))
        #expect(filter.sanitize(String(repeating: "9", count: 15) + ".99") == String(repeating: "9", count: 12) + ".99")
    }

    @Test func maxInputStillFitsInt64MinorUnits() throws {
        let filter = AmountInputFilter(currency: .kwd, locale: enUS)
        let money = try #require(filter.money(from: filter.sanitize(String(repeating: "9", count: 20) + ".999")))
        #expect(throws: Never.self) { try money.amountMinor() }
    }

    @Test func emptyMeansNoAmountNotZero() {
        let filter = AmountInputFilter(currency: .sgd, locale: enUS)
        #expect(filter.money(from: "") == nil)
        #expect(filter.money(from: "0") == Money.zero(.sgd))
    }

    @Test func parsesWithLocaleSeparator() {
        #expect(
            AmountInputFilter(currency: .sgd, locale: enUS).money(from: "12.5")
                == Money(amountMinor: 1250, currency: .sgd))
        #expect(
            AmountInputFilter(currency: .eur, locale: deDE).money(from: "12,5")
                == Money(amountMinor: 1250, currency: .eur))
        #expect(
            AmountInputFilter(currency: .sgd, locale: enUS).money(from: "12.")
                == Money(amountMinor: 1200, currency: .sgd))
        #expect(AmountInputFilter(currency: .sgd, locale: enUS).money(from: "0.") == Money.zero(.sgd))
    }

    @Test func prefillTextUsesLocaleSeparator() {
        let money = Money(amountMinor: 820_050, currency: .eur)
        #expect(AmountInputFilter(currency: .eur, locale: deDE).text(for: money) == "8200,5")
        #expect(AmountInputFilter(currency: .eur, locale: enUS).text(for: money) == "8200.5")
    }

    @Test func prefillIsEmptyForNilOrNegative() {
        let filter = AmountInputFilter(currency: .sgd, locale: enUS)
        #expect(filter.text(for: nil) == "")
        #expect(filter.text(for: Money(amountMinor: -500, currency: .sgd)) == "")
    }

    @Test(arguments: [Currency.jpy, .sgd, .kwd])
    func prefillRoundTrips(currency: Currency) {
        let money = Money(amountMinor: 123_456, currency: currency)
        for locale in [enUS, deDE] {
            let filter = AmountInputFilter(currency: currency, locale: locale)
            let text = filter.text(for: money)
            #expect(filter.sanitize(text) == text)
            #expect(filter.money(from: text) == money)
        }
    }
}
