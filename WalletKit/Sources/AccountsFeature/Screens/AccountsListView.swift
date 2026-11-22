import DesignSystem
import Domain
import SwiftUI

/// One card per currency. Renders `AccountsListViewModel.State`; every action goes
/// back to the view model.
struct AccountsListView: View {
    let viewModel: AccountsListViewModel
    /// Bumped by Retry. The `.task(id:)` below does the work, so it is cancelled with the screen.
    @State private var retryRequests = 0

    var body: some View {
        Group {
            if viewModel.state.showsFullScreenError, let error = viewModel.state.error {
                ErrorStateView(error: error) {
                    retryRequests += 1
                }
            } else if !viewModel.state.hasLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .background(Palette.background)
        .navigationTitle(AccountsStrings.title)
        .task(id: retryRequests) {
            if retryRequests == 0 {
                await viewModel.onAppear()
            } else {
                await viewModel.retry()
            }
        }
    }

    private var list: some View {
        List {
            if viewModel.state.showsBanner, let error = viewModel.state.error {
                Text(error.canRetry ? AccountsStrings.couldNotUpdate : error.message)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityIdentifier("accounts.banner")
            }
            if viewModel.state.showsEmpty {
                Text(AccountsStrings.noAccounts)
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityIdentifier("accounts.empty")
            }
            ForEach(viewModel.state.accounts) { account in
                Button {
                    viewModel.select(account)
                } label: {
                    AccountCard(account: account)
                }
                .accessibilityIdentifier("accounts.card.\(account.id)")
            }
        }
        .groupedListStyle()
        .refreshable {
            await viewModel.refresh()
        }
    }
}

#if DEBUG
    #Preview("Light") {
        NavigationStack {
            AccountsListView(viewModel: .preview(PreviewAccountsRepository()))
        }
    }

    #Preview("Dark") {
        NavigationStack {
            AccountsListView(viewModel: .preview(PreviewAccountsRepository()))
        }
        .preferredColorScheme(.dark)
    }

    #Preview("Accessibility 5") {
        NavigationStack {
            AccountsListView(viewModel: .preview(PreviewAccountsRepository()))
        }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
    }

    #Preview("Offline") {
        NavigationStack {
            AccountsListView(viewModel: .preview(PreviewAccountsRepository(failure: .offline)))
        }
    }

    extension AccountsListViewModel {
        static func preview(_ repository: PreviewAccountsRepository) -> AccountsListViewModel {
            AccountsListViewModel(
                dependencies: AccountsDependencies(repository: repository),
                router: AccountsRouter(),
                onSessionExpired: {}
            )
        }
    }
#endif
