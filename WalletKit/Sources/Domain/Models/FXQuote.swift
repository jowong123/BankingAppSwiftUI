import Foundation

/// A server-issued, time-limited price for a transfer (docs/SPEC.md section 5).
public struct FXQuote: Hashable, Sendable, Identifiable {
    public let id: String
    public let sourceAmount: Money
    public let targetAmount: Money
    public let rate: FXRate
    public let fee: Money
    public let expiresAt: Date

    /// Throws if the amounts don't match the rate's currencies, or the fee isn't in the
    /// source currency. The fee is deducted before conversion (SPEC section 5):
    /// `targetAmount = round((sourceAmount - fee) * rate)`, so the user is debited exactly
    /// `sourceAmount`. The server computes the amounts; this only checks the currencies.
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
        guard fee.currency == rate.source else {
            throw .currencyMismatch(expected: rate.source, actual: fee.currency)
        }
        self.id = id
        self.sourceAmount = sourceAmount
        self.targetAmount = targetAmount
        self.rate = rate
        self.fee = fee
        self.expiresAt = expiresAt
    }

    /// The client's own check of the server's maths (Phase 3 carry-over): the fee is not
    /// negative and less than the amount, `target = round((source - fee) * rate)` to within
    /// one minor unit, and the quote hasn't expired. A quote that fails is never shown, so the
    /// user never approves numbers that don't add up.
    public func addsUp(at now: Date) -> Bool {
        guard !fee.isNegative,
            (try? fee.compare(to: sourceAmount)) == .orderedAscending,
            let net = try? sourceAmount.subtracting(fee),
            let expected = try? rate.convert(net).amountMinor(),
            let actual = try? targetAmount.amountMinor()
        else {
            return false
        }
        // A hostile amount near Int64's limits must not crash the check.
        let (difference, overflow) = expected.subtractingReportingOverflow(actual)
        return !overflow && (-1...1).contains(difference) && !isExpired(at: now)
    }

    /// `now` is passed in rather than read from the clock so callers and tests control time.
    public func isExpired(at now: Date) -> Bool {
        now >= expiresAt
    }
}
