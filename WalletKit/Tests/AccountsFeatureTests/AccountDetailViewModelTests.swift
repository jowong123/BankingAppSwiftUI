import Domain
import Testing

@testable import AccountsFeature

@MainActor
@Suite struct AccountDetailViewModelTests {
    let repository = FakeAccountsRepository()
    let sessionExpired = CallCounter()

    func makeViewModel(initial: Account? = sampleAccounts[0]) -> AccountDetailViewModel {
        AccountDetailViewModel(
            accountID: "acc_sgd",
            initial: initial,
            dependencies: AccountsDependencies(repository: repository),
            onSessionExpired: { [sessionExpired] in
                sessionExpired.record()
            }
        )
    }

    @Test func loadsTheFirstPage() async {
        await repository.setPage(cursor: nil, page(["t1", "t2"], next: "c2"))
        let viewModel = makeViewModel()

        await viewModel.onAppear()

        #expect(viewModel.state.transactions.map(\.id) == ["t1", "t2"])
        #expect(viewModel.state.canLoadMore)
        #expect(await repository.transactionCursors == [nil])
    }

    @Test func loadMoreAppendsTheNextPageUsingItsCursor() async {
        await repository.setPage(cursor: nil, page(["t1", "t2"], next: "c2"))
        await repository.setPage(cursor: "c2", page(["t3"], next: nil))
        let viewModel = makeViewModel()
        await viewModel.onAppear()

        await viewModel.loadMore()

        #expect(viewModel.state.transactions.map(\.id) == ["t1", "t2", "t3"])
        #expect(!viewModel.state.canLoadMore)
        #expect(await repository.transactionCursors == [nil, "c2"])
    }

    @Test func atTheEndOfTheListLoadMoreDoesNothing() async {
        await repository.setPage(cursor: nil, page(["t1"], next: nil))
        let viewModel = makeViewModel()
        await viewModel.onAppear()

        await viewModel.loadMore()

        #expect(await repository.transactionCursors == [nil])
    }

    @Test func emptyHistoryShowsTheEmptyState() async {
        await repository.setPage(cursor: nil, page([], next: nil))
        let viewModel = makeViewModel()

        await viewModel.onAppear()

        #expect(viewModel.state.showsEmpty)
    }

    /// The footer's `.task` can fire again while a page is loading; only one request goes out.
    @Test func loadMoreTwiceAtOnceSendsOneRequest() async {
        await repository.setPage(cursor: nil, page(["t1"], next: "c2"))
        await repository.setPage(cursor: "c2", page(["t2"], next: nil))
        let viewModel = makeViewModel()
        await viewModel.onAppear()
        let gate = Gate()
        await repository.holdPage(cursor: "c2", with: gate)
        let first = Task {
            await viewModel.loadMore()
        }
        await waitUntil {
            await repository.transactionCursors.count == 2
        }

        await viewModel.loadMore()
        await gate.open()
        await first.value

        #expect(await repository.transactionCursors == [nil, "c2"])
        #expect(viewModel.state.transactions.map(\.id) == ["t1", "t2"])
    }

    @Test func refreshStartsAgainFromTheNewestPage() async {
        await repository.setPage(cursor: nil, page(["t1"], next: "c2"))
        await repository.setPage(cursor: "c2", page(["t2"], next: nil))
        let viewModel = makeViewModel()
        await viewModel.onAppear()
        await viewModel.loadMore()
        await repository.setPage(cursor: nil, page(["t0", "t1"], next: "c2"))

        await viewModel.refresh()

        #expect(viewModel.state.transactions.map(\.id) == ["t0", "t1"])
        #expect(viewModel.state.canLoadMore)
    }

    /// A next page that arrives after a refresh belongs to the old list and is dropped.
    @Test func pageThatFinishesAfterARefreshIsDropped() async {
        await repository.setPage(cursor: nil, page(["t1"], next: "c2"))
        await repository.setPage(cursor: "c2", page(["old"], next: nil))
        let viewModel = makeViewModel()
        await viewModel.onAppear()
        let gate = Gate()
        await repository.holdPage(cursor: "c2", with: gate)
        let stale = Task {
            await viewModel.loadMore()
        }
        await waitUntil {
            await repository.transactionCursors.count == 2
        }

        // The refresh finishes first; only then does the old next page arrive.
        await repository.setPage(cursor: nil, page(["new"], next: nil))
        await viewModel.refresh()
        await gate.open()
        await stale.value

        #expect(viewModel.state.transactions.map(\.id) == ["new"])
        #expect(!viewModel.state.isLoadingMore)
        #expect(!viewModel.state.isLoadingFirstPage)
    }

    @Test func duplicateRowsFromTheServerAreShownOnce() async {
        await repository.setPage(cursor: nil, page(["t1", "t2"], next: "c2"))
        await repository.setPage(cursor: "c2", page(["t2", "t3"], next: nil))
        let viewModel = makeViewModel()
        await viewModel.onAppear()

        await viewModel.loadMore()

        #expect(viewModel.state.transactions.map(\.id) == ["t1", "t2", "t3"])
    }

    @Test func firstPageOfflineShowsAFullScreenErrorThenRetryLoads() async {
        await repository.setPage(cursor: nil, .failure(.offline))
        let viewModel = makeViewModel()
        await viewModel.onAppear()
        #expect(viewModel.state.showsFullScreenError)

        await repository.setPage(cursor: nil, page(["t1"], next: nil))
        await viewModel.retry()

        #expect(!viewModel.state.showsFullScreenError)
        #expect(viewModel.state.transactions.map(\.id) == ["t1"])
    }

    @Test func nextPageFailureKeepsTheRowsAndRetryLoadsThatPage() async {
        await repository.setPage(cursor: nil, page(["t1"], next: "c2"))
        await repository.setPage(cursor: "c2", .failure(.offline))
        let viewModel = makeViewModel()
        await viewModel.onAppear()
        await viewModel.loadMore()

        #expect(viewModel.state.showsLoadMoreError)
        #expect(!viewModel.state.showsFullScreenError)
        #expect(viewModel.state.transactions.map(\.id) == ["t1"])

        await repository.setPage(cursor: "c2", page(["t2"], next: nil))
        await viewModel.retry()

        #expect(viewModel.state.transactions.map(\.id) == ["t1", "t2"])
        #expect(viewModel.state.error == nil)
        #expect(await repository.transactionCursors == [nil, "c2", "c2"])
    }

    @Test func failedRefreshKeepsTheRowsWithABannerAndRetryRefreshes() async {
        await repository.setPage(cursor: nil, page(["t1"], next: nil))
        let viewModel = makeViewModel()
        await viewModel.onAppear()
        await repository.setPage(cursor: nil, .failure(.unavailable))

        await viewModel.refresh()

        #expect(viewModel.state.showsRefreshBanner)
        #expect(viewModel.state.transactions.map(\.id) == ["t1"])

        await repository.setPage(cursor: nil, page(["t0", "t1"], next: nil))
        await viewModel.retry()

        #expect(viewModel.state.transactions.map(\.id) == ["t0", "t1"])
        #expect(!viewModel.state.showsRefreshBanner)
    }

    @Test func cancellationShowsNoError() async {
        await repository.setPage(cursor: nil, .failure(.cancelled))
        let viewModel = makeViewModel()

        await viewModel.onAppear()

        #expect(viewModel.state.error == nil)
        #expect(!viewModel.state.isLoadingFirstPage)
    }

    @Test func showsTheListsBalanceAtOnceThenTheFreshOne() async {
        let fresh = Account(id: "acc_sgd", balance: Money(amountMinor: 999_900, currency: .sgd), updatedAt: .now)
        await repository.setAccounts([.success([fresh])])
        await repository.setPage(cursor: nil, page(["t1"], next: nil))
        let viewModel = makeViewModel()
        #expect(viewModel.state.account == sampleAccounts[0])

        await viewModel.onAppear()

        #expect(viewModel.state.account == fresh)
    }

    /// The balance must never be older than the list: pull to refresh re-reads it.
    @Test func refreshUpdatesTheBalance() async {
        await repository.setPage(cursor: nil, page(["t1"], next: nil))
        let viewModel = makeViewModel()
        await viewModel.onAppear()
        let fresh = Account(id: "acc_sgd", balance: Money(amountMinor: 1, currency: .sgd), updatedAt: .now)
        await repository.setAccounts([.success([fresh])])

        await viewModel.refresh()

        #expect(viewModel.state.account?.balance == fresh.balance)
    }

    @Test func withoutAnInitialAccountTheBalanceArrivesWithTheFirstLoad() async {
        await repository.setPage(cursor: nil, page(["t1"], next: nil))
        let viewModel = makeViewModel(initial: nil)
        #expect(viewModel.state.account == nil)

        await viewModel.onAppear()

        #expect(viewModel.state.account == sampleAccounts[0])
    }

    @Test func accountMissingFromTheServerIsAnError() async {
        await repository.setAccounts([.success([sampleAccounts[1]])])
        await repository.setPage(cursor: nil, page(["t1"], next: nil))
        let viewModel = makeViewModel()

        await viewModel.onAppear()

        #expect(viewModel.state.showsFullScreenError)
    }

    /// Loading more must not hide a failed refresh: the first page is still stale.
    @Test func loadingMoreAfterAFailedRefreshKeepsTheBanner() async {
        await repository.setPage(cursor: nil, page(["t1"], next: "c2"))
        await repository.setPage(cursor: "c2", page(["t2"], next: nil))
        let viewModel = makeViewModel()
        await viewModel.onAppear()
        await repository.setPage(cursor: nil, .failure(.unavailable))
        await viewModel.refresh()
        #expect(viewModel.state.showsRefreshBanner)

        await viewModel.loadMore()

        #expect(viewModel.state.transactions.map(\.id) == ["t1", "t2"])
        #expect(viewModel.state.showsRefreshBanner)
    }

    @Test func expiredSessionTellsTheApp() async {
        await repository.setPage(cursor: nil, .failure(.sessionExpired))
        let viewModel = makeViewModel()

        await viewModel.onAppear()

        #expect(sessionExpired.calls == 1)
        #expect(viewModel.state.error?.canRetry == false)
    }
}
