import Foundation
import Testing

@testable import Domain

@Suite struct AccountTests {
    @Test func currencyComesFromTheBalance() {
        let account = Account(id: "acc_jpy", balance: Money(amountMinor: 150_000, currency: .jpy), updatedAt: .now)

        #expect(account.currency == .jpy)
    }

    @Test(arguments: [
        (Int64(-450), AccountTransaction.Direction.outgoing),
        (1, .incoming),
        (0, .incoming),
    ])
    func directionFollowsTheSignOfTheAmount(minor: Int64, expected: AccountTransaction.Direction) {
        let transaction = AccountTransaction(
            id: "txn_1",
            accountID: "acc_sgd",
            amount: Money(amountMinor: minor, currency: .sgd),
            description: "Kopi Corner",
            createdAt: .now
        )

        #expect(transaction.direction == expected)
    }

    @Test func pageWithACursorHasMore() {
        #expect(TransactionPage(items: [], nextCursor: "c2").hasMore)
        #expect(!TransactionPage(items: [], nextCursor: nil).hasMore)
    }
}
