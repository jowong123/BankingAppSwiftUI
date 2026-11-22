import Domain
import Foundation
import NetworkingKit
import Testing

@testable import Networking

@Suite struct RemoteAccountsRepositoryTests {
    @Test func returnsDomainAccounts() async throws {
        let body = """
            {"accounts":[{"id":"acc_kwd","currency":"KWD",
              "balance":{"amountMinor":120500,"currency":"KWD"},"updatedAt":"2026-10-26T10:00:00Z"}]}
            """
        let repository = RemoteAccountsRepository(api: try makeAPI(StubTransport([status(200, body)])))

        let accounts = try await repository.accounts()

        #expect(accounts.map(\.id) == ["acc_kwd"])
        #expect(accounts.first?.balance == Money(amountMinor: 120_500, currency: .kwd))
    }

    /// One account in a currency the app doesn't know fails the whole list, rather than
    /// silently showing fewer balances than the user has.
    @Test func oneUnknownCurrencyRejectsTheWholeList() async throws {
        let body = """
            {"accounts":[
              {"id":"acc_sgd","currency":"SGD","balance":{"amountMinor":100,"currency":"SGD"},"updatedAt":"2026-10-26T10:00:00Z"},
              {"id":"acc_chf","currency":"CHF","balance":{"amountMinor":100,"currency":"CHF"},"updatedAt":"2026-10-26T10:00:00Z"}]}
            """
        let repository = RemoteAccountsRepository(api: try makeAPI(StubTransport([status(200, body)])))

        await #expect(throws: DataSourceError.invalidData) {
            try await repository.accounts()
        }
    }

    @Test func passesTheCursorThrough() async throws {
        let transport = StubTransport([status(200, #"{"items":[],"nextCursor":"c_3"}"#)])
        let repository = RemoteAccountsRepository(api: try makeAPI(transport))

        let page = try await repository.transactions(accountID: "acc_sgd", cursor: "c_2")

        #expect(page.nextCursor == "c_3")
        let query = await transport.requests.first?.url?.query() ?? ""
        #expect(query.contains("cursor=c_2"))
    }

    @Test func offlineBecomesOffline() async throws {
        let repository = RemoteAccountsRepository(
            api: try makeAPI(StubTransport([.failure(.transport(.notConnectedToInternet))])))

        await #expect(throws: DataSourceError.offline) {
            try await repository.accounts()
        }
    }

    /// Features act on these four outcomes; the HTTP detail stays in Networking.
    @Test(arguments: [
        (APIError.transport(.timedOut), DataSourceError.offline),
        (.transport(.dataNotAllowed), .offline),
        // Refused, no such host, TLS: the server can't be reached, the connection is fine.
        (.transport(.cannotConnectToHost), .unavailable),
        (.transport(.cannotFindHost), .unavailable),
        (.transport(.serverCertificateUntrusted), .unavailable),
        (.unauthorized, .sessionExpired),
        (.cancelled, .cancelled),
        (.http(status: 503), .unavailable),
        (.server(status: 500, code: "internal", message: "", requestID: nil), .unavailable),
        (.http(status: 429), .unavailable),
        (.http(status: 408), .unavailable),
        (.server(status: 404, code: "not_found", message: "", requestID: nil), .invalidData),
        (.http(status: 400), .invalidData),
        (.invalidResponse("unsupported currency"), .invalidData),
        (.invalidRequest, .invalidData),
    ])
    func apiErrorsMapToWhatTheUserCanDo(error: APIError, expected: DataSourceError) {
        #expect(error.dataSourceError == expected)
    }
}

@Suite struct AccountDTOMappingTests {
    @Test func accountWhoseCurrencyDisagreesWithItsBalanceIsRejected() throws {
        let data = Data(
            #"""
            {"id":"acc_sgd","currency":"USD","balance":{"amountMinor":100,"currency":"SGD"},
             "updatedAt":"2026-10-26T10:00:00Z"}
            """#.utf8)
        let dto = try WalletJSON.decoder().decode(AccountDTO.self, from: data)

        #expect(throws: APIError.invalidResponse("account currency")) {
            try dto.account()
        }
    }

    @Test func recipientWithAnUnknownCurrencyIsRejected() throws {
        let data = Data(#"{"id":"rcp_1","name":"Alice","currency":"CHF","accountLast4":"1234"}"#.utf8)
        let dto = try WalletJSON.decoder().decode(RecipientDTO.self, from: data)

        #expect(throws: APIError.invalidResponse("unsupported currency")) {
            try dto.recipient()
        }
    }

    @Test func recipientMapsToDomain() throws {
        let data = Data(#"{"id":"rcp_1","name":"Alice","currency":"USD","accountLast4":"1234"}"#.utf8)

        let recipient = try WalletJSON.decoder().decode(RecipientDTO.self, from: data).recipient()

        #expect(recipient == Recipient(id: "rcp_1", name: "Alice", currency: .usd, accountLast4: "1234"))
    }
}
