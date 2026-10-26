import Foundation

/// A server-issued, time-limited price for a transfer (docs/SPEC.md section 5).
public struct FXQuote: Hashable, Sendable, Identifiable {
    public let id: String
    public let sourceAmount: Money
    public let targetAmount: Money
    public let rate: FXRate
    public let fee: Money
    public let expiresAt: Date

    /// Throws if the amounts don't match the rate's currencies. The fee's currency isn't
    /// checked yet: the spec doesn't say which side it's charged in (decide in Phase 3).
    public init(
        id: String,
        sourceAmount: Money,
        targetAmount: Money,
        rate: FXRate,
        fee: Money,
        expiresAt: Date
    ) throws(MoneyError) {
        guard sourceAmount.currency == rate.source else {
            throw .currencyMismatch(expected: rate.source, actual: sourceAmount.currency)
        }
        guard targetAmount.currency == rate.target else {
            throw .currencyMismatch(expected: rate.target, actual: targetAmount.currency)
        }
        self.id = id
        self.sourceAmount = sourceAmount
        self.targetAmount = targetAmount
        self.rate = rate
        self.fee = fee
        self.expiresAt = expiresAt
    }

    /// `now` is passed in rather than read from the clock so callers and tests control time.
    public func isExpired(at now: Date) -> Bool {
        now >= expiresAt
    }
}
