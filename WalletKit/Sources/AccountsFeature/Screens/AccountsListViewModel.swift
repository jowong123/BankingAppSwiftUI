import Domain
import Observation

/// Balances per currency. Online only (ADR-017): nothing is cached on the device, so a
/// cold start without a connection shows an error, never old numbers.
@Observable @MainActor
final class AccountsListViewModel {
    struct State: Equatable {
        var accounts: [Account] = []
        var isLoading = false
        var hasLoaded = false
        var error: UserFacingError?

        /// No balances to show: the error takes the whole screen.
        var showsFullScreenError: Bool {
            error != nil && accounts.isEmpty
        }
        /// A refresh failed but this session's balances are still on screen: a banner.
        var showsBanner: Bool {
            error != nil && !accounts.isEmpty
        }
        var showsEmpty: Bool {
            hasLoaded && accounts.isEmpty && error == nil
        }
    }

    private(set) var state = State()
    private let repository: any AccountsRepository
    private let router: AccountsRouter
    private let onSessionExpired: @MainActor () -> Void

    init(dependencies: AccountsDependencies, router: AccountsRouter, onSessionExpired: @escaping @MainActor () -> Void)
    {
        self.repository = dependencies.repository
        self.router = router
        self.onSessionExpired = onSessionExpired
    }

    /// Loads once. Coming back from a detail screen doesn't reload.
    func onAppear() async {
        guard !state.hasLoaded else {
            return
        }
        await load()
    }

    /// If a load is already running this returns at once and that load's result is used,
    /// so a pull to refresh during the first load never sends a second request.
    func refresh() async {
        await load()
    }

    func retry() async {
        await load()
    }

    func select(_ account: Account) {
        router.push(.accountDetail(accountID: account.id))
    }

    private func load() async {
        guard !state.isLoading else {
            return
        }
        state.isLoading = true
        defer {
            state.isLoading = false
        }
        do throws(DataSourceError) {
            let accounts = try await repository.accounts()
            state.accounts = accounts
            state.hasLoaded = true
            state.error = nil
        } catch {
            if error == .sessionExpired {
                onSessionExpired()
            }
            // Cancellation means the screen went away: keep whatever was there.
            if let shown = AccountsError.userFacing(error) {
                state.error = shown
            }
        }
    }
}
