/// Currencies the sandbox supports, with ISO 4217 minor units. Must match the app's
/// `Currency.supported` table.
enum Currencies {
    static let minorUnits: [String: Int] = ["SGD": 2, "USD": 2, "EUR": 2, "JPY": 0, "KWD": 3]

    static func isSupported(_ code: String) -> Bool {
        minorUnits[code] != nil
    }
}
