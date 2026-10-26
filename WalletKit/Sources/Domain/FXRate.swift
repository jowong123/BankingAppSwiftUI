import Foundation

/// How many units of `target` one unit of `source` buys.
public struct FXRate: Hashable, Sendable {
    public let source: Currency
    public let target: Currency
    /// Kept at full precision; only converted amounts are rounded.
    public let rate: Decimal

    public init(source: Currency, target: Currency, rate: Decimal) throws(MoneyError) {
        guard rate > 0 else { throw .invalidRate }
        self.source = source
        self.target = target
        self.rate = rate
    }

    /// Converts a source amount, rounding the result to the target currency's minor units.
    public func convert(_ money: Money) throws(MoneyError) -> Money {
        guard money.currency == source else {
            throw .currencyMismatch(expected: source, actual: money.currency)
        }
        return Money(amount: money.amount * rate, currency: target)
    }
}
