import AccountsFeature
import Domain
import Foundation
import Testing

@testable import Wallet

@MainActor
struct AppEnvironmentTests {
    @Test func liveEnvironmentLinksEveryAppFacingModule() {
        let environment = AppEnvironment.live(arguments: ["-mockServer"])

        #expect(Set(environment.linkedModules).count == 11)
    }

    @Test func simulateOfflineArgumentMakesMockAccountsFailOffline() async {
        let environment = AppEnvironment.live(arguments: ["-mockServer", "-uiTesting", "-simulateOffline"])

        await #expect(throws: DataSourceError.offline) {
            try await environment.accounts.repository.accounts()
        }
    }

    @Test(arguments: [
        ("http://127.0.0.1:8080", true), ("https://api.wallet.invalid", true), ("not a url", false), ("", false),
    ])
    func baseURLComesFromInfoPlist(value: String, valid: Bool) {
        #expect((AppEnvironment.baseURL(from: ["WalletAPIBaseURL": value]) != nil) == valid)
        #expect(AppEnvironment.baseURL(from: nil) == nil)
    }

    /// The Debug build talks to the local backend; the exception for plain http is Debug only (ADR-018).
    @Test func debugBuildPointsAtTheLocalBackend() {
        #expect(AppEnvironment.baseURL(from: Bundle.main.infoDictionary)?.absoluteString == "http://127.0.0.1:8080")
        let ats = Bundle.main.infoDictionary?["NSAppTransportSecurity"] as? [String: Any]
        #expect(ats?["NSAllowsLocalNetworking"] as? Bool == true)
        #expect(ats?["NSAllowsArbitraryLoads"] == nil)
    }

    @Test func faceIDUsageDescriptionIsSet() {
        #expect((Bundle.main.infoDictionary?["NSFaceIDUsageDescription"] as? String)?.isEmpty == false)
    }
}

struct MockAccountsRepositoryTests {
    let repository = MockAccountsRepository(isOffline: false, delay: .zero)

    @Test func hasTheBackendSeedBalances() async throws {
        let accounts = try await repository.accounts()

        #expect(accounts.map(\.id) == ["acc_sgd", "acc_usd", "acc_jpy", "acc_kwd"])
        #expect(accounts.first?.balance == Money(amountMinor: 1_250_000, currency: .sgd))
    }

    /// 45 SGD transactions: pages of 20, 20 and 5, newest first, no gaps or repeats.
    @Test func sgdHistoryPagesThroughEveryTransactionOnce() async throws {
        var ids: [String] = []
        var cursor: String?
        var pages = 0
        repeat {
            let page = try await repository.transactions(accountID: "acc_sgd", cursor: cursor)
            ids += page.items.map(\.id)
            cursor = page.nextCursor
            pages += 1
        } while cursor != nil

        #expect(pages == 3)
        #expect(ids.count == 45)
        #expect(Set(ids).count == 45)
        #expect(ids.first == "txn_sgd_44")
    }

    @Test func badCursorIsInvalidData() async {
        await #expect(throws: DataSourceError.invalidData) {
            try await repository.transactions(accountID: "acc_sgd", cursor: "999")
        }
    }
}
