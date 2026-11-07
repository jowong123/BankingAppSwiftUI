import Domain
import Foundation

struct AccountDTO: Decodable, Hashable, Sendable {
    let id: String
    let currency: String
    let balance: MoneyDTO
    let updatedAt: Date

    func account() throws(APIError) -> Account {
        let balance = try balance.money()
        // The account's currency is sent twice; a mismatch means the payload is wrong.
        guard balance.currency.code == currency else {
            throw .invalidResponse("account currency")
        }
        return Account(id: id, balance: balance, updatedAt: updatedAt)
    }
}

struct AccountsResponseDTO: Decodable, Sendable {
    let accounts: [AccountDTO]
}

struct TransactionDTO: Decodable, Hashable, Sendable {
    let id: String
    let accountId: String
    /// Signed: negative for money out.
    let amount: MoneyDTO
    let description: String
    let createdAt: Date

    func transaction() throws(APIError) -> AccountTransaction {
        AccountTransaction(
            id: id,
            accountID: accountId,
            amount: try amount.money(),
            description: description,
            createdAt: createdAt
        )
    }
}

/// One page of history. `nextCursor` is `nil` on the last page.
struct TransactionPageDTO: Decodable, Hashable, Sendable {
    let items: [TransactionDTO]
    let nextCursor: String?

    func page() throws(APIError) -> TransactionPage {
        var transactions: [AccountTransaction] = []
        for item in items {
            transactions.append(try item.transaction())
        }
        return TransactionPage(items: transactions, nextCursor: nextCursor)
    }
}

struct RecipientDTO: Decodable, Hashable, Sendable {
    let id: String
    let name: String
    let currency: String
    /// Only the last four digits ever leave the server.
    let accountLast4: String

    func recipient() throws(APIError) -> Recipient {
        guard let currency = Currency.supported(code: currency) else {
            throw .invalidResponse("unsupported currency")
        }
        return Recipient(id: id, name: name, currency: currency, accountLast4: accountLast4)
    }
}

struct RecipientsResponseDTO: Decodable, Sendable {
    let recipients: [RecipientDTO]
}
