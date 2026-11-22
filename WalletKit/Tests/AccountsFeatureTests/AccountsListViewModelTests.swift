import Domain
import SwiftUI
import Testing

@testable import AccountsFeature

@MainActor
@Suite struct AccountsListViewModelTests {
    let repository = FakeAccountsRepository()
    let router = AccountsRouter()
    let sessionExpired = CallCounter()

    func makeViewModel() -> AccountsListViewModel {
        AccountsListViewModel(
            dependencies: AccountsDependencies(repository: repository),
            router: router,
            onSessionExpired: { [sessionExpired] in
                sessionExpired.record()
            }
        )
    }

    @Test func startsEmptyAndNotLoaded() {
        let state = makeViewModel().state

        #expect(state.accounts.isEmpty)
        #expect(!state.hasLoaded)
        #expect(!state.isLoading)
        #expect(state.error == nil)
    }

    @Test func appearingLoadsTheBalances() async {
        let viewModel = makeViewModel()

        await viewModel.onAppear()

        #expect(viewModel.state.accounts == sampleAccounts)
        #expect(viewModel.state.hasLoaded)
        #expect(!viewModel.state.isLoading)
        #expect(viewModel.state.error == nil)
    }

    @Test func appearingAgainDoesNotReload() async {
        let viewModel = makeViewModel()

        await viewModel.onAppear()
        await viewModel.onAppear()

        #expect(await repository.accountsCalls == 1)
    }

    /// Online only: with no connection on a cold start there is nothing to show but the error.
    @Test func coldStartOfflineShowsAFullScreenErrorAndNoBalances() async {
        await repository.setAccounts([.failure(.offline)])
        let viewModel = makeViewModel()

        await viewModel.onAppear()

        #expect(viewModel.state.accounts.isEmpty)
        #expect(viewModel.state.showsFullScreenError)
        #expect(viewModel.state.error?.title == AccountsStrings.offlineTitle)
        #expect(viewModel.state.error?.canRetry == true)
    }

    @Test func failedRefreshKeepsThisSessionsBalancesWithABanner() async {
        await repository.setAccounts([.success(sampleAccounts), .failure(.unavailable)])
        let viewModel = makeViewModel()
        await viewModel.onAppear()

        await viewModel.refresh()

        #expect(viewModel.state.accounts == sampleAccounts)
        #expect(viewModel.state.showsBanner)
        #expect(!viewModel.state.showsFullScreenError)
    }

    @Test func retryAfterAFailureLoadsAndClearsTheError() async {
        await repository.setAccounts([.failure(.offline), .success(sampleAccounts)])
        let viewModel = makeViewModel()
        await viewModel.onAppear()

        await viewModel.retry()

        #expect(viewModel.state.accounts == sampleAccounts)
        #expect(viewModel.state.error == nil)
    }

    @Test func expiredSessionOffersNoRetryAndTellsTheApp() async {
        await repository.setAccounts([.failure(.sessionExpired)])
        let viewModel = makeViewModel()

        await viewModel.onAppear()

        #expect(viewModel.state.error?.title == AccountsStrings.sessionExpiredTitle)
        #expect(viewModel.state.error?.canRetry == false)
        #expect(sessionExpired.calls == 1)
    }

    @Test func sessionExpiringOnRefreshTellsTheAppAndKeepsTheBanner() async {
        await repository.setAccounts([.success(sampleAccounts), .failure(.sessionExpired)])
        let viewModel = makeViewModel()
        await viewModel.onAppear()

        await viewModel.refresh()

        #expect(sessionExpired.calls == 1)
        #expect(viewModel.state.showsBanner)
        #expect(viewModel.state.error?.canRetry == false)
    }

    @Test func offlineDoesNotTellTheAppTheSessionEnded() async {
        await repository.setAccounts([.failure(.offline)])
        let viewModel = makeViewModel()

        await viewModel.onAppear()

        #expect(sessionExpired.calls == 0)
    }

    @Test func noAccountsShowsTheEmptyState() async {
        await repository.setAccounts([.success([])])
        let viewModel = makeViewModel()

        await viewModel.onAppear()

        #expect(viewModel.state.showsEmpty)
        #expect(!viewModel.state.showsFullScreenError)
    }

    @Test func cancellationShowsNoError() async {
        await repository.setAccounts([.failure(.cancelled)])
        let viewModel = makeViewModel()

        await viewModel.onAppear()

        #expect(viewModel.state.error == nil)
        #expect(!viewModel.state.isLoading)
    }

    @Test func refreshWhileLoadingDoesNotStartASecondRequest() async {
        let gate = Gate()
        await repository.holdAccounts(call: 1, with: gate)
        let viewModel = makeViewModel()
        let first = Task {
            await viewModel.onAppear()
        }
        await waitUntil {
            await repository.accountsCalls == 1
        }

        await viewModel.refresh()
        await gate.open()
        await first.value

        #expect(await repository.accountsCalls == 1)
        #expect(viewModel.state.accounts == sampleAccounts)
    }

    @Test func selectingAnAccountPushesItsDetail() {
        let viewModel = makeViewModel()

        viewModel.select(sampleAccounts[0])

        #expect(router.path == NavigationPath([AccountsRoute.accountDetail(accountID: "acc_sgd")]))
    }
}
