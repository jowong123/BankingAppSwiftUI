/// Errors from building or combining `Currency`, `Money` and `FXRate` values.
public enum MoneyError: Error, Equatable, Sendable {
    /// The code is not three uppercase ASCII letters, or minor units are outside 0...4.
    case invalidCurrency(code: String, minorUnits: Int)
    /// Arithmetic or comparison between two different currencies.
    case currencyMismatch(expected: Currency, actual: Currency)
    /// The amount does not fit in `Int64` minor units.
    case overflow
    /// An FX rate that is zero or negative.
    case invalidRate
}
