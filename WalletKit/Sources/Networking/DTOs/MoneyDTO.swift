import Domain
import Foundation

/// Money on the wire: `{ "amountMinor": 125000, "currency": "SGD" }`. Never a float.
struct MoneyDTO: Codable, Hashable, Sendable {
    let amountMinor: Int64
    let currency: String

    init(amountMinor: Int64, currency: String) {
        self.amountMinor = amountMinor
        self.currency = currency
    }

    init(_ money: Money) throws(APIError) {
        do {
            self.init(amountMinor: try money.amountMinor(), currency: money.currency.code)
        } catch {
            throw .invalidRequest
        }
    }

    /// The minor units come from the app's currency table, not the server, so an
    /// unknown code is rejected instead of guessed (`Currency.supported`).
    func money() throws(APIError) -> Money {
        guard let currency = Currency.supported(code: currency) else {
            throw .invalidResponse("unsupported currency")
        }
        return Money(amountMinor: amountMinor, currency: currency)
    }
}
