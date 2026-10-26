import Foundation

/// An amount in one currency, always rounded to that currency's minor units.
///
/// `Decimal` keeps base-10 amounts exact (0.1 + 0.2 == 0.3), which `Double` cannot.
/// Rounding happens once, in the initialiser, with banker's rounding (half to even)
/// so repeated rounding across many transactions does not drift upwards.
public struct Money: Hashable, Sendable {
    public let amount: Decimal
    public let currency: Currency

    public init(amount: Decimal, currency: Currency) {
        self.amount = Self.rounded(amount, to: currency.minorUnits)
        self.currency = currency
    }

    /// Builds from the integer minor-unit amount used at the API boundary (e.g. 1050 SGD cents).
    public init(amountMinor: Int64, currency: Currency) {
        // significand × 10^-minorUnits is exact in Decimal; no division, no rounding.
        let scale = Decimal(sign: .plus, exponent: -currency.minorUnits, significand: 1)
        self.init(amount: Decimal(amountMinor) * scale, currency: currency)
    }

    public static func zero(_ currency: Currency) -> Money {
        Money(amount: 0, currency: currency)
    }

    public var isZero: Bool { amount.isZero }
    public var isNegative: Bool { amount < 0 }

    /// The integer minor-unit amount for the API (`amountMinor: Int64`).
    public func amountMinor() throws(MoneyError) -> Int64 {
        let scale = Decimal(sign: .plus, exponent: currency.minorUnits, significand: 1)
        let minor = amount * scale
        guard minor >= Decimal(Int64.min), minor <= Decimal(Int64.max) else { throw .overflow }
        // `amount` is already rounded, so `minor` is a whole number and its description
        // is plain digits. NSDecimalNumber.int64Value is avoided: it loses precision near the limits.
        guard let value = Int64(minor.description) else { throw .overflow }
        return value
    }

    public func adding(_ other: Money) throws(MoneyError) -> Money {
        try requireSameCurrency(other)
        return Money(amount: amount + other.amount, currency: currency)
    }

    public func subtracting(_ other: Money) throws(MoneyError) -> Money {
        try requireSameCurrency(other)
        return Money(amount: amount - other.amount, currency: currency)
    }

    public func negated() -> Money {
        Money(amount: -amount, currency: currency)
    }

    /// Ordering is only meaningful within one currency, so this throws instead of
    /// conforming to `Comparable` (whose `<` cannot report a mismatch).
    public func compare(to other: Money) throws(MoneyError) -> ComparisonResult {
        try requireSameCurrency(other)
        if amount < other.amount { return .orderedAscending }
        if amount > other.amount { return .orderedDescending }
        return .orderedSame
    }

    /// Locale-aware display, e.g. "$8,200.00" (en_US) or "S$8,200.00" (en_SG).
    /// Always shows exactly `minorUnits` decimals, whatever the locale's default is.
    public func formatted(locale: Locale) -> String {
        amount.formatted(
            .currency(code: currency.code)
                .locale(locale)
                .precision(.fractionLength(currency.minorUnits))
        )
    }

    /// VoiceOver text with the currency spelled out, e.g. "8,200.00 US dollars".
    public func accessibilityLabel(locale: Locale) -> String {
        amount.formatted(
            .currency(code: currency.code)
                .locale(locale)
                .precision(.fractionLength(currency.minorUnits))
                .presentation(.fullName)
        )
    }

    private func requireSameCurrency(_ other: Money) throws(MoneyError) {
        guard other.currency == currency else {
            throw .currencyMismatch(expected: currency, actual: other.currency)
        }
    }

    private static func rounded(_ value: Decimal, to scale: Int) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .bankers)
        return result
    }
}
