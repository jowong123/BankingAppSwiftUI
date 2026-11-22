import Domain
import Observation

/// One account's balance and history, newest first, loaded a page at a time as the user
/// scrolls. Pull to refresh re-reads the balance too, so it is never older than the list.
@Observable @MainActor
final class AccountDetailViewModel {
    /// Which load the current `error` came from, so Retry repeats the right one.
    enum FailedLoad: Equatable {
        case firstPage
        case nextPage
    }

    struct State: Equatable {
        /// Starts with what the list showed, then replaced by each refresh.
        var account: Account?
        var transactions: [AccountTransaction] = []
        var nextCursor: String?
        var hasLoadedFirstPage = false
        var isLoadingFirstPage = false
        var isLoadingMore = false
        var error: UserFacingError?
        var failedLoad: FailedLoad?

        var canLoadMore: Bool {
            hasLoadedFirstPage && nextCursor != nil
        }
        var showsFullScreenError: Bool {
            error != nil && !hasLoadedFirstPage
        }
        var showsEmpty: Bool {
            hasLoadedFirstPage && transactions.isEmpty && error == nil
        }
        /// A refresh failed while older rows are on screen.
        var showsRefreshBanner: Bool {
            error != nil && hasLoadedFirstPage && failedLoad == .firstPage
        }
        /// The next page failed: the footer explains, with Retry when it can help.
        var showsLoadMoreError: Bool {
            error != nil && failedLoad == .nextPage
        }
    }

    let accountID: Account.ID
    private(set) var state = State()
    private let repository: any AccountsRepository
    private let onSessionExpired: @MainActor () -> Void
    private let onSendMoney: @MainActor (Account) -> Void
    /// Bumped by every first-page load. A next-page request that started before a
    /// refresh finishes with an older value and is dropped, so a stale page is never
    /// appended to the fresh list.
    private var generation = 0

    /// - Parameter initial: the account as the list showed it, so the balance appears at
    ///   once. `nil` (e.g. a future deep link) shows it after the first load.
    init(
        accountID: Account.ID,
        initial: Account?,
        dependencies: AccountsDependencies,
        onSessionExpired: @escaping @MainActor () -> Void,
        onSendMoney: @escaping @MainActor (Account) -> Void = { _ in }
    ) {
        self.accountID = accountID
        self.repository = dependencies.repository
        self.onSessionExpired = onSessionExpired
        self.onSendMoney = onSendMoney
        state.account = initial
    }

    func onAppear() async {
        guard !state.hasLoadedFirstPage else {
            return
        }
        await loadFirstPage()
    }

    /// Hands the account to `AppCoordinator`, which opens the send-money flow.
    func sendMoney() {
        if let account = state.account {
            onSendMoney(account)
        }
    }

    /// Pull to refresh: the balance and the newest page again.
    func refresh() async {
        await loadFirstPage()
    }

    /// Called when the end of the list comes into view.
    func loadMore() async {
        guard state.canLoadMore, !state.isLoadingMore, !state.isLoadingFirstPage,
            let cursor = state.nextCursor
        else {
            return
        }
        let started = generation
        state.isLoadingMore = true
        defer {
            if started == generation {
                state.isLoadingMore = false
            }
        }
        do throws(DataSourceError) {
            let page = try await repository.transactions(accountID: accountID, cursor: cursor)
            guard started == generation else {
                return
            }
            // Keyset pagination shouldn't repeat rows, but never show one twice.
            let known = Set(state.transactions.map(\.id))
            state.transactions += page.items.filter {
                !known.contains($0.id)
            }
            state.nextCursor = page.nextCursor
            // Only clear our own failure: a failed-refresh banner stays until a refresh works.
            if state.failedLoad == .nextPage {
                state.error = nil
                state.failedLoad = nil
            }
        } catch {
            guard started == generation else {
                return
            }
            record(error, from: .nextPage)
        }
    }

    func retry() async {
        if state.failedLoad == .nextPage {
            await loadMore()
        } else {
            await loadFirstPage()
        }
    }

    /// The balance, then the newest page, both under one generation.
    private func loadFirstPage() async {
        generation += 1
        let started = generation
        state.isLoadingFirstPage = true
        state.isLoadingMore = false
        defer {
            if started == generation {
                state.isLoadingFirstPage = false
            }
        }
        do throws(DataSourceError) {
            let accounts = try await repository.accounts()
            let page = try await repository.transactions(accountID: accountID, cursor: nil)
            guard started == generation else {
                return
            }
            guard
                let account = accounts.first(where: {
                    $0.id == accountID
                })
            else {
                throw .invalidData
            }
            state.account = account
            state.transactions = page.items
            state.nextCursor = page.nextCursor
            state.hasLoadedFirstPage = true
            state.error = nil
            state.failedLoad = nil
        } catch {
            guard started == generation else {
                return
            }
            record(error, from: .firstPage)
        }
    }

    /// Cancellation means the screen went away: leave the state as it was.
    private func record(_ error: DataSourceError, from load: FailedLoad) {
        if error == .sessionExpired {
            onSessionExpired()
        }
        guard let shown = AccountsError.userFacing(error) else {
            return
        }
        state.error = shown
        state.failedLoad = load
    }
}
