import Domain
import SwiftUI

/// The only public view of the feature: the accounts list, and the screens it pushes.
///
/// - Parameters:
///   - reloadTrigger: bump it to refresh what is on screen, e.g. after a transfer.
///   - onSessionExpired: the server says the session can't be renewed. `AppCoordinator`
///     goes back to sign-in.
///   - onSendMoney: "Send money" on an account. `AppCoordinator` opens the transfer flow.
public struct AccountsFlowView: View {
    @Bindable private var router: AccountsRouter
    @State private var listViewModel: AccountsListViewModel
    private let dependencies: AccountsDependencies
    private let reloadTrigger: Int
    private let onSessionExpired: @MainActor () -> Void
    private let onSendMoney: @MainActor (Account) -> Void

    public init(
        router: AccountsRouter,
        dependencies: AccountsDependencies,
        reloadTrigger: Int = 0,
        onSessionExpired: @escaping @MainActor () -> Void,
        onSendMoney: @escaping @MainActor (Account) -> Void
    ) {
        self.router = router
        self.dependencies = dependencies
        self.reloadTrigger = reloadTrigger
        self.onSessionExpired = onSessionExpired
        self.onSendMoney = onSendMoney
        _listViewModel = State(
            initialValue: AccountsListViewModel(
                dependencies: dependencies,
                router: router,
                onSessionExpired: onSessionExpired
            ))
    }

    public var body: some View {
        NavigationStack(path: $router.path) {
            AccountsListView(viewModel: listViewModel)
                .navigationDestination(for: AccountsRoute.self) { route in
                    destination(for: route)
                }
        }
        .task(id: reloadTrigger) {
            if reloadTrigger > 0 {
                await listViewModel.refresh()
            }
        }
    }

    @ViewBuilder private func destination(for route: AccountsRoute) -> some View {
        switch route {
        case .accountDetail(let accountID):
            AccountDetailScreen(
                accountID: accountID,
                initial: listViewModel.state.accounts.first {
                    $0.id == accountID
                },
                dependencies: dependencies,
                reloadTrigger: reloadTrigger,
                onSessionExpired: onSessionExpired,
                onSendMoney: onSendMoney
            )
        }
    }
}

/// Owns the detail view model for as long as the screen is on the stack.
private struct AccountDetailScreen: View {
    @State private var viewModel: AccountDetailViewModel
    private let reloadTrigger: Int

    init(
        accountID: Account.ID,
        initial: Account?,
        dependencies: AccountsDependencies,
        reloadTrigger: Int,
        onSessionExpired: @escaping @MainActor () -> Void,
        onSendMoney: @escaping @MainActor (Account) -> Void
    ) {
        self.reloadTrigger = reloadTrigger
        _viewModel = State(
            initialValue: AccountDetailViewModel(
                accountID: accountID,
                initial: initial,
                dependencies: dependencies,
                onSessionExpired: onSessionExpired,
                onSendMoney: onSendMoney
            ))
    }

    var body: some View {
        AccountDetailView(viewModel: viewModel)
            .task(id: reloadTrigger) {
                if reloadTrigger > 0 {
                    await viewModel.refresh()
                }
            }
    }
}
