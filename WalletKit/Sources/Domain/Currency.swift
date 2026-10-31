import Foundation

/// An ISO 4217 currency and how many decimal places its smallest unit has.
///
/// `minorUnits` drives rounding and the `amountMinor` conversion in `Money`,
/// so it must match ISO 4217 (SGD 2, JPY 0, KWD 3), not the locale's display.
public struct Currency: Hashable, Sendable {
    public let code: String
    public let minorUnits: Int

    /// Validates the code shape and the minor-unit range; it does not check the code
    /// against the ISO list, so the backend can add currencies without an app release.
    public init(code: String, minorUnits: Int) throws(MoneyError) {
        let isISOShape = code.count == 3 && code.allSatisfy { $0.isASCII && $0.isUppercase }
        guard isISOShape, (0...4).contains(minorUnits) else {
            throw .invalidCurrency(code: code, minorUnits: minorUnits)
        }
        self.code = code
        self.minorUnits = minorUnits
    }

    /// For the known constants below only, whose values are checked by hand.
    private init(knownCode code: String, minorUnits: Int) {
        self.code = code
        self.minorUnits = minorUnits
    }

    public static let sgd = Currency(knownCode: "SGD", minorUnits: 2)
    public static let usd = Currency(knownCode: "USD", minorUnits: 2)
    public static let eur = Currency(knownCode: "EUR", minorUnits: 2)
    public static let jpy = Currency(knownCode: "JPY", minorUnits: 0)
    public static let kwd = Currency(knownCode: "KWD", minorUnits: 3)

    /// Currencies the app knows the ISO 4217 minor units for. The API sends only the code
    /// (`{ "amountMinor", "currency" }`), so decoding money needs this table.
    public static let supported: [Currency] = [.sgd, .usd, .eur, .jpy, .kwd]

    /// The supported currency with this code, or `nil` if the app doesn't know it.
    public static func supported(code: String) -> Currency? {
        supported.first { $0.code == code }
    }
}
