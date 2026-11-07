import Domain
import SwiftUI

/// The only public view of the feature: the accounts list, and the screens it pushes.
///
/// - Parameter onSessionExpired: called when the server says the session can't be renewed.
///   `AppCoordinator` decides what happens (Phase 5: back to sign-in). "Send money"
///   becomes a second output in Phase 6.
public struct AccountsFlowView: View {
    @Bindable private var router: AccountsRouter
    @State private var listViewModel: AccountsListViewModel
    private let dependencies: AccountsDependencies
    private let onSessionExpired: @MainActor () -> Void

    public init(
        router: AccountsRouter,
        dependencies: AccountsDependencies,
        onSessionExpired: @escaping @MainActor () -> Void
    ) {
        self.router = router
        self.dependencies = dependencies
        self.onSessionExpired = onSessionExpired
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
                onSessionExpired: onSessionExpired
            )
        }
    }
}

/// Owns the detail view model for as long as the screen is on the stack.
private struct AccountDetailScreen: View {
    @State private var viewModel: AccountDetailViewModel

    init(
        accountID: Account.ID,
        initial: Account?,
        dependencies: AccountsDependencies,
        onSessionExpired: @escaping @MainActor () -> Void
    ) {
        _viewModel = State(
            initialValue: AccountDetailViewModel(
                accountID: accountID,
                initial: initial,
                dependencies: dependencies,
                onSessionExpired: onSessionExpired
            ))
    }

    var body: some View {
        AccountDetailView(viewModel: viewModel)
    }
}
