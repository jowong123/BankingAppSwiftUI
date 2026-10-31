import Foundation

public struct AccountDTO: Decodable, Hashable, Sendable {
    public let id: String
    public let currency: String
    public let balance: MoneyDTO
    public let updatedAt: Date
}

struct AccountsResponseDTO: Decodable, Sendable {
    let accounts: [AccountDTO]
}

public struct TransactionDTO: Decodable, Hashable, Sendable {
    public let id: String
    public let accountId: String
    /// Signed: negative for money out.
    public let amount: MoneyDTO
    public let description: String
    public let createdAt: Date
}

/// One page of history. `nextCursor` is `nil` on the last page.
public struct TransactionPageDTO: Decodable, Hashable, Sendable {
    public let items: [TransactionDTO]
    public let nextCursor: String?
}

public struct RecipientDTO: Decodable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let currency: String
    /// Only the last four digits ever leave the server.
    public let accountLast4: String
}

struct RecipientsResponseDTO: Decodable, Sendable {
    let recipients: [RecipientDTO]
}
