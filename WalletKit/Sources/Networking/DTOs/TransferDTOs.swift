import Domain
import Foundation

struct QuoteRequestDTO: Encodable, Sendable {
    let sourceAmount: MoneyDTO
    let targetCurrency: String
}

struct QuoteDTO: Decodable, Sendable {
    let id: String
    let sourceAmount: MoneyDTO
    let targetAmount: MoneyDTO
    let fee: MoneyDTO
    /// A decimal string such as "0.741234", so the rate never passes through `Double`.
    let rate: String
    let expiresAt: Date

    func quote() throws(APIError) -> FXQuote {
        let source = try sourceAmount.money()
        let target = try targetAmount.money()
        let fee = try fee.money()
        // Decimal(string:) parses a prefix ("1,5" is 1, "1.2abc" is 1.2), so check the format first.
        guard rate.wholeMatch(of: /[0-9]+(\.[0-9]+)?/) != nil,
            let rateValue = Decimal(string: rate, locale: Locale(identifier: "en_US_POSIX"))
        else {
            throw .invalidResponse("rate")
        }
        do {
            let rate = try FXRate(source: source.currency, target: target.currency, rate: rateValue)
            return try FXQuote(
                id: id,
                sourceAmount: source,
                targetAmount: target,
                rate: rate,
                fee: fee,
                expiresAt: expiresAt
            )
        } catch {
            throw .invalidResponse("quote")
        }
    }
}

struct TransferCreateDTO: Encodable, Sendable {
    let id: String
    let quoteId: String
    let recipientId: String
    let sourceAccountId: String
}

public struct TransferDTO: Decodable, Hashable, Sendable {
    public enum Status: String, Decodable, Hashable, Sendable {
        /// Created; waiting for the signed confirm (Phase 7).
        case awaitingConfirmation = "awaiting_confirmation"
        case processing
        case completed
        case failed
        /// A status this app version doesn't know. Treated as still in progress.
        case unknown

        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Status(rawValue: raw) ?? .unknown
        }
    }

    public let id: String
    public let quoteId: String
    public let recipientId: String
    public let sourceAccountId: String
    public let sourceAmount: MoneyDTO
    public let targetAmount: MoneyDTO
    public let fee: MoneyDTO
    public let status: Status
    /// Server reason code when `status == .failed`, e.g. "declined".
    public let failureReason: String?
    public let createdAt: Date
    public let updatedAt: Date
}
