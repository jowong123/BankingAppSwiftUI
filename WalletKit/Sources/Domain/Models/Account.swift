import Foundation

/// One currency balance the user holds (`GET /v1/accounts`, SPEC section 7).
public struct Account: Hashable, Sendable, Identifiable {
    public let id: String
    public let balance: Money
    public let updatedAt: Date

    /// Taken from the balance, so the two can never disagree.
    public var currency: Currency {
        balance.currency
    }

    public init(id: String, balance: Money, updatedAt: Date) {
        self.id = id
        self.balance = balance
        self.updatedAt = updatedAt
    }
}
