import Foundation
import Testing

@testable import Domain

@Suite struct MoneyRoundingTests {
    /// Banker's rounding (half to even) at each currency's minor units.
    /// Ties are the interesting rows: they go to the even neighbour, not always up.
    @Test(arguments: [
        // JPY, 0 decimals
        (Currency.jpy, "2.5", "2"),
        (.jpy, "3.5", "4"),
        (.jpy, "-2.5", "-2"),
        (.jpy, "-3.5", "-4"),
        (.jpy, "1.4", "1"),
        (.jpy, "1.6", "2"),
        (.jpy, "1234", "1234"),
        // SGD, 2 decimals
        (.sgd, "1.005", "1"),
        (.sgd, "1.015", "1.02"),
        (.sgd, "1.025", "1.02"),
        (.sgd, "-1.015", "-1.02"),
        (.sgd, "10.994", "10.99"),
        (.sgd, "10.996", "11"),
        (.sgd, "0.1", "0.1"),
        // KWD, 3 decimals
        (.kwd, "0.0125", "0.012"),
        (.kwd, "0.0135", "0.014"),
        (.kwd, "1.2345", "1.234"),
        (.kwd, "1.2355", "1.236"),
        (.kwd, "-0.0005", "0"),
        (.kwd, "1.5", "1.5"),
    ])
    func roundsHalfToEven(currency: Currency, input: String, expected: String) throws {
        let money = Money(amount: try decimal(input), currency: currency)
        #expect(money.amount == (try decimal(expected)))
    }

    @Test func decimalAvoidsBinaryFloatingPointError() throws {
        // 0.1 + 0.2 is 0.30000000000000004 in Double.
        let sum = try Money(amount: decimal("0.1"), currency: .sgd)
            .adding(Money(amount: decimal("0.2"), currency: .sgd))
        #expect(sum.amount == (try decimal("0.3")))
    }
}

@Suite struct MoneyMinorUnitTests {
    @Test(arguments: [
        (Currency.sgd, "10.5", Int64(1050)),
        (.sgd, "0.01", 1),
        (.sgd, "-10.5", -1050),
        (.jpy, "1234", 1234),
        (.kwd, "1.5", 1500),
        (.kwd, "0.001", 1),
        (.usd, "0", 0),
    ])
    func convertsBothWays(currency: Currency, amount: String, minor: Int64) throws {
        let money = Money(amount: try decimal(amount), currency: currency)
        #expect(try money.amountMinor() == minor)
        #expect(Money(amountMinor: minor, currency: currency) == money)
    }

    @Test(arguments: [Currency.jpy, .sgd, .kwd])
    func roundTripsAtInt64Limits(currency: Currency) throws {
        for limit in [Int64.max, Int64.min] {
            let money = Money(amountMinor: limit, currency: currency)
            #expect(try money.amountMinor() == limit)
        }
    }

    @Test(arguments: [Currency.jpy, .sgd, .kwd])
    func throwsOverflowJustPastInt64Limits(currency: Currency) {
        let oneMinorUnit = Money(amountMinor: 1, currency: currency).amount
        let aboveMax = Money(
            amount: Money(amountMinor: .max, currency: currency).amount + oneMinorUnit, currency: currency)
        let belowMin = Money(
            amount: Money(amountMinor: .min, currency: currency).amount - oneMinorUnit, currency: currency)
        #expect(throws: MoneyError.overflow) { try aboveMax.amountMinor() }
        #expect(throws: MoneyError.overflow) { try belowMin.amountMinor() }
    }

    @Test func nanThrowsOverflowInsteadOfCrashing() {
        let money = Money(amount: .nan, currency: .sgd)
        #expect(throws: MoneyError.overflow) { try money.amountMinor() }
    }
}

@Suite struct MoneyArithmeticTests {
    let tenSGD = Money(amountMinor: 1000, currency: .sgd)
    let threeSGD = Money(amountMinor: 300, currency: .sgd)
    let tenUSD = Money(amountMinor: 1000, currency: .usd)

    @Test func addsAndSubtractsSameCurrency() throws {
        #expect(try tenSGD.adding(threeSGD) == Money(amountMinor: 1300, currency: .sgd))
        #expect(try tenSGD.subtracting(threeSGD) == Money(amountMinor: 700, currency: .sgd))
        #expect(try threeSGD.subtracting(tenSGD) == Money(amountMinor: -700, currency: .sgd))
    }

    @Test func mixedCurrenciesThrow() {
        let mismatch = MoneyError.currencyMismatch(expected: .sgd, actual: .usd)
        #expect(throws: mismatch) { try tenSGD.adding(tenUSD) }
        #expect(throws: mismatch) { try tenSGD.subtracting(tenUSD) }
        #expect(throws: mismatch) { try tenSGD.compare(to: tenUSD) }
    }

    @Test func comparesWithinOneCurrency() throws {
        #expect(try threeSGD.compare(to: tenSGD) == .orderedAscending)
        #expect(try tenSGD.compare(to: threeSGD) == .orderedDescending)
        #expect(try tenSGD.compare(to: tenSGD) == .orderedSame)
    }

    @Test func negatedAndZero() {
        #expect(tenSGD.negated() == Money(amountMinor: -1000, currency: .sgd))
        #expect(tenSGD.negated().isNegative)
        #expect(Money.zero(.kwd).isZero)
        #expect(!Money.zero(.kwd).isNegative)
        #expect(Money.zero(.kwd).negated().isZero)
    }

    @Test func equalityIgnoresTrailingZeros() throws {
        let one = Money(amount: try decimal("1.0"), currency: .sgd)
        let onePointZeroZero = Money(amount: try decimal("1.00"), currency: .sgd)
        #expect(one == onePointZeroZero)
        #expect(Set([one, onePointZeroZero]).count == 1)
    }

    @Test func sameAmountDifferentCurrencyIsNotEqual() {
        #expect(tenSGD != tenUSD)
    }
}

@Suite struct MoneyFormattingTests {
    // Exact strings vary with the OS's ICU data (spaces, currency symbols), so these
    // check the parts that matter: grouping, decimal count and the currency name.
    let enUS = Locale(identifier: "en_US")

    @Test func showsExactlyTheMinorUnits() {
        #expect(Money(amountMinor: 820_050, currency: .usd).formatted(locale: enUS).contains("8,200.50"))
        #expect(Money(amountMinor: 820_000, currency: .usd).formatted(locale: enUS).contains("8,200.00"))
        #expect(Money(amountMinor: 1500, currency: .kwd).formatted(locale: enUS).contains("1.500"))
        let yen = Money(amountMinor: 1234, currency: .jpy).formatted(locale: enUS)
        #expect(yen.contains("1,234"))
        #expect(!yen.contains("."))
    }

    @Test func followsTheLocale() {
        let german = Money(amountMinor: 820_050, currency: .eur).formatted(locale: Locale(identifier: "de_DE"))
        #expect(german.contains("8.200,50"))
    }

    @Test func accessibilityLabelSpellsOutCurrency() {
        let label = Money(amountMinor: 820_050, currency: .usd).accessibilityLabel(locale: enUS)
        #expect(label.contains("8,200.50"))
        #expect(label.contains("US dollars"))
    }
}
