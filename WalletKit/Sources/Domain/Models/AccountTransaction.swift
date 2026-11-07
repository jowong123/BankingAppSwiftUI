import Foundation

/// One entry in an account's history.
///
/// Not called `Transaction`: SwiftUI has a `Transaction` type, and every feature view
/// imports both SwiftUI and Domain.
public struct AccountTransaction: Hashable, Sendable, Identifiable {
    public enum Direction: Hashable, Sendable {
        case incoming
        case outgoing
    }

    public let id: String
    public let accountID: String
    /// Signed: negative is money out.
    public let amount: Money
    public let description: String
    public let createdAt: Date

    public init(id: String, accountID: String, amount: Money, description: String, createdAt: Date) {
        self.id = id
        self.accountID = accountID
        self.amount = amount
        self.description = description
        self.createdAt = createdAt
    }

    public var direction: Direction {
        amount.isNegative ? .outgoing : .incoming
    }
}

/// One page of history, newest first. `nextCursor` is opaque; pass it back to get the
/// next page. `nil` means this is the last page.
public struct TransactionPage: Hashable, Sendable {
    public let items: [AccountTransaction]
    public let nextCursor: String?

    public init(items: [AccountTransaction], nextCursor: String?) {
        self.items = items
        self.nextCursor = nextCursor
    }

    public var hasMore: Bool {
        nextCursor != nil
    }
}
