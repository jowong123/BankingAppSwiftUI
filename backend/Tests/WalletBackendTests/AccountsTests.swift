import XCTVapor

@testable import WalletBackend

final class AccountsTests: XCTestCase {
    func testAccountsAreTheSignedInUsersOnlyInMinorUnits() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()

            let response = try await harness.send(.GET, "/v1/accounts", token: tokens.accessToken)

            let accounts = try response.content.decode(AccountsResponse.self).accounts
            XCTAssertEqual(accounts.map(\.id), ["acc_jpy", "acc_kwd", "acc_sgd", "acc_usd"])
            let kwd = try XCTUnwrap(accounts.first { $0.currency == "KWD" })
            XCTAssertEqual(kwd.balance, MoneyDTO(amountMinor: 120_500, currency: "KWD"))
        }
    }

    func testBalanceIsAnIntegerOnTheWire() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()

            let response = try await harness.send(.GET, "/v1/accounts", token: tokens.accessToken)

            let body = try XCTUnwrap(response.body.string)
            XCTAssertTrue(body.contains(#""amountMinor":1250000"#), body)
            XCTAssertFalse(body.contains("12500.0"))
        }
    }

    func testTransactionsPageThroughEverythingNewestFirstWithoutGapsOrDuplicates() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()
            var seen: [TransactionDTO] = []
            var cursor: String?
            var pages = 0

            repeat {
                let query = cursor.map {
                    "&cursor=\($0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0)"
                }
                let response = try await harness.send(
                    .GET,
                    "/v1/accounts/acc_sgd/transactions?limit=20\(query ?? "")",
                    token: tokens.accessToken
                )
                XCTAssertEqual(response.status, .ok)
                let page = try response.content.decode(TransactionPage.self)
                seen += page.items
                cursor = page.nextCursor
                pages += 1
            } while cursor != nil && pages < 10

            XCTAssertEqual(pages, 3)
            XCTAssertEqual(seen.count, 45)
            XCTAssertEqual(Set(seen.map(\.id)).count, 45)
            XCTAssertEqual(seen.map(\.createdAt), seen.map(\.createdAt).sorted(by: >))
            XCTAssertTrue(seen.allSatisfy { $0.accountId == "acc_sgd" })
        }
    }

    func testLastPageHasNoCursor() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()

            let response = try await harness.send(.GET, "/v1/accounts/acc_kwd/transactions", token: tokens.accessToken)

            let page = try response.content.decode(TransactionPage.self)
            XCTAssertEqual(page.items.count, 1)
            XCTAssertNil(page.nextCursor)
        }
    }

    func testAnotherUsersAccountIsNotFound() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()

            let response = try await harness.send(
                .GET,
                "/v1/accounts/acc_other_sgd/transactions",
                token: tokens.accessToken
            )

            XCTAssertEqual(response.status, .notFound)
            XCTAssertEqual(response.envelope?.code, "not_found")
        }
    }

    func testInvalidLimitAndCursorAreRejected() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()

            for query in ["limit=0", "limit=101", "cursor=not-base64!", "cursor=Zm9v"] {
                let response = try await harness.send(
                    .GET,
                    "/v1/accounts/acc_sgd/transactions?\(query)",
                    token: tokens.accessToken
                )
                XCTAssertEqual(response.status, .badRequest, query)
                XCTAssertEqual(response.envelope?.code, "bad_request", query)
            }
        }
    }

    func testRecipientsAreTheSignedInUsersOnly() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()

            let response = try await harness.send(.GET, "/v1/recipients", token: tokens.accessToken)

            let recipients = try response.content.decode(RecipientsResponse.self).recipients
            XCTAssertEqual(recipients.count, 4)
            XCTAssertFalse(recipients.contains { $0.id == "rcp_other_usd" })
            XCTAssertTrue(recipients.allSatisfy { $0.accountLast4.count == 4 })
        }
    }
}
