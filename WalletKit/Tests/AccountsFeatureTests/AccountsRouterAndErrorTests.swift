import Domain
import Testing

@testable import AccountsFeature

@MainActor
@Suite struct AccountsRouterTests {
    @Test func pushPopAndPopToRoot() {
        let router = AccountsRouter()

        router.push(.accountDetail(accountID: "acc_sgd"))
        router.push(.accountDetail(accountID: "acc_jpy"))
        #expect(router.path.count == 2)

        router.pop()
        #expect(router.path.count == 1)

        router.popToRoot()
        #expect(router.path.isEmpty)

        router.pop()
        #expect(router.path.isEmpty)
    }

    @Test func presentAndDismiss() {
        let router = AccountsRouter()

        router.present(.accountDetail(accountID: "acc_sgd"))
        #expect(router.sheet == .accountDetail(accountID: "acc_sgd"))

        router.dismiss()
        #expect(router.sheet == nil)
    }
}

@Suite struct AccountsErrorTests {
    @Test(arguments: [
        (DataSourceError.offline, true),
        (.unavailable, true),
        (.invalidData, true),
        (.sessionExpired, false),
    ])
    func everyFailureBecomesAMessage(error: DataSourceError, canRetry: Bool) throws {
        let shown = try #require(AccountsError.userFacing(error))

        #expect(!shown.title.isEmpty)
        #expect(!shown.message.isEmpty)
        #expect(shown.canRetry == canRetry)
    }

    @Test func cancellationIsNotShown() {
        #expect(AccountsError.userFacing(.cancelled) == nil)
    }
}
