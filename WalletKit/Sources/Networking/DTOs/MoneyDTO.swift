import Domain
import Foundation

/// Money on the wire: `{ "amountMinor": 125000, "currency": "SGD" }`. Never a float.
public struct MoneyDTO: Codable, Hashable, Sendable {
    public let amountMinor: Int64
    public let currency: String

    public init(amountMinor: Int64, currency: String) {
        self.amountMinor = amountMinor
        self.currency = currency
    }

    public init(_ money: Money) throws(APIError) {
        do {
            self.init(amountMinor: try money.amountMinor(), currency: money.currency.code)
        } catch {
            throw .invalidRequest
        }
    }

    /// The minor units come from the app's currency table, not the server, so an
    /// unknown code is rejected instead of guessed (`Currency.supported`).
    public func money() throws(APIError) -> Money {
        guard let currency = Currency.supported(code: currency) else {
            throw .invalidResponse("unsupported currency")
        }
        return Money(amountMinor: amountMinor, currency: currency)
    }
}

/// `{ "code", "message", "requestId" }`, the body of every non-2xx response.
struct ErrorEnvelopeDTO: Decodable {
    let code: String
    let message: String
    let requestId: String?
}
