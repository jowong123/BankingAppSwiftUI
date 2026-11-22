import Foundation
import Testing

/// Exact decimal from a string literal. `Decimal(2.675)` would go through `Double` first.
func decimal(_ text: String) throws -> Decimal {
    try #require(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")))
}
