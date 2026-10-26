import Domain
import Foundation

/// The text rules behind `AmountField`, kept out of the view so they can be tested.
///
/// Turns whatever the user typed or pasted into a valid amount string for the currency,
/// and parses that string into `Money` without going through `Double`.
struct AmountInputFilter: Sendable {
    let currency: Currency
    let decimalSeparator: String
    /// 12 integer digits is far beyond any wallet balance and keeps `amountMinor`
    /// well inside `Int64` even for 3-decimal currencies.
    let maxIntegerDigits = 12

    init(currency: Currency, locale: Locale) {
        self.currency = currency
        self.decimalSeparator = locale.decimalSeparator ?? "."
    }

    /// Keeps digits and the first decimal separator, drops extra decimals and leading zeros.
    ///
    /// Only the locale's decimal separator counts; every other character, including grouping
    /// separators, is dropped. So "1,234.50" in en_US and "1.234,50" in de_DE both work.
    /// A paste written in another locale's convention (e.g. "12.50" in de_DE, read as 1250)
    /// cannot be told apart from grouping, so the field shows the parsed amount and the
    /// confirm screen shows the formatted `Money` before anything is sent.
    /// Digits from any script (e.g. Arabic-Indic) are normalised to ASCII.
    func sanitize(_ text: String) -> String {
        var integer = ""
        var fraction = ""
        var hasSeparator = false
        var sawDigit = false

        for character in text {
            if let digit = character.wholeNumberValue, (0...9).contains(digit), character.isNumber {
                sawDigit = true
                if hasSeparator {
                    if fraction.count < currency.minorUnits { fraction += String(digit) }
                } else if integer.count < maxIntegerDigits {
                    integer += String(digit)
                }
            } else if String(character) == decimalSeparator {
                // Still marks where the fraction starts for JPY, so "1.5" truncates to 1
                // instead of joining into 15; the separator itself is only kept below.
                hasSeparator = true
            }
        }

        integer = String(integer.drop { $0 == "0" })
        if integer.isEmpty, hasSeparator || sawDigit { integer = "0" }
        // Currencies with no minor units (JPY) never show a separator.
        return hasSeparator && currency.minorUnits > 0 ? integer + decimalSeparator + fraction : integer
    }

    /// Parses a sanitized string. Empty input means "no amount yet", not zero.
    func money(from text: String) -> Money? {
        guard !text.isEmpty else { return nil }
        let normalized = text.replacingOccurrences(of: decimalSeparator, with: ".")
        guard let amount = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        return Money(amount: amount, currency: currency)
    }

    /// The editable text for an existing amount, e.g. when a field is prefilled.
    /// Negative amounts can't be typed, so they show as empty rather than as text
    /// that the next keystroke would silently strip.
    func text(for money: Money?) -> String {
        guard let money, !money.isNegative else { return "" }
        return money.amount.description.replacingOccurrences(of: ".", with: decimalSeparator)
    }
}
