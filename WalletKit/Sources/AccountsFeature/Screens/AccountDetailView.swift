import DesignSystem
import Domain
import SwiftUI

/// The balance on top, then the history. Reaching the end of the list loads the next page.
struct AccountDetailView: View {
    let viewModel: AccountDetailViewModel
    /// Bumped by Retry. The `.task(id:)` below does the work, so it is cancelled with the screen.
    @State private var retryRequests = 0

    var body: some View {
        Group {
            if viewModel.state.showsFullScreenError, let error = viewModel.state.error {
                ErrorStateView(error: error) {
                    retryRequests += 1
                }
            } else {
                list
            }
        }
        .background(Palette.background)
        .navigationTitle(viewModel.state.account?.currency.code ?? "")
        .inlineNavigationTitle()
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
            if let account = viewModel.state.account {
                Section {
                    AmountText(account.balance, style: .hero)
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityIdentifier("account.balance")
                    Button(AccountsStrings.sendMoney) {
                        viewModel.sendMoney()
                    }
                    .accessibilityIdentifier("account.sendMoney")
                }
            }
            Section {
                if viewModel.state.showsRefreshBanner, let error = viewModel.state.error {
                    Text(error.canRetry ? AccountsStrings.couldNotUpdate : error.message)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
                if viewModel.state.showsEmpty {
                    Text(AccountsStrings.noTransactions)
                        .foregroundStyle(Palette.textSecondary)
                }
                ForEach(viewModel.state.transactions) { transaction in
                    TransactionRow(
                        title: transaction.description,
                        subtitle: transaction.createdAt.formatted(date: .abbreviated, time: .shortened),
                        amount: transaction.amount,
                        direction: transaction.direction == .incoming ? .incoming : .outgoing
                    )
                    .accessibilityIdentifier("account.transaction.\(transaction.id)")
                }
                footer
            }
        }
        .groupedListStyle()
        .refreshable {
            await viewModel.refresh()
        }
    }

    @ViewBuilder private var footer: some View {
        if viewModel.state.showsLoadMoreError, let error = viewModel.state.error {
            VStack(spacing: Spacing.small) {
                Text(error.canRetry ? AccountsStrings.couldNotLoadMore : error.message)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                if error.canRetry {
                    Button(AccountsStrings.retry) {
                        retryRequests += 1
                    }
                    .accessibilityIdentifier("account.loadMore.retry")
                }
            }
            .frame(maxWidth: .infinity)
        } else if viewModel.state.canLoadMore {
            // Appears when the user scrolls to the end, which starts the next page. Keyed on
            // the cursor and the first-page load, so a scroll that hit the end during a
            // refresh tries again once the refresh is done.
            ProgressView()
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("account.loadMore")
                .task(id: "\(viewModel.state.nextCursor ?? "")|\(viewModel.state.isLoadingFirstPage)") {
                    await viewModel.loadMore()
                }
        }
    }
}

#if DEBUG
    #Preview("Light") {
        NavigationStack {
            AccountDetailView(viewModel: .preview(PreviewAccountsRepository()))
        }
    }

    #Preview("Dark") {
        NavigationStack {
            AccountDetailView(viewModel: .preview(PreviewAccountsRepository()))
        }
        .preferredColorScheme(.dark)
    }

    #Preview("Accessibility 5") {
        NavigationStack {
            AccountDetailView(viewModel: .preview(PreviewAccountsRepository()))
        }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
    }

    extension AccountDetailViewModel {
        static func preview(_ repository: PreviewAccountsRepository) -> AccountDetailViewModel {
            AccountDetailViewModel(
                accountID: PreviewAccountsRepository.sampleAccounts[0].id,
                initial: PreviewAccountsRepository.sampleAccounts[0],
                dependencies: AccountsDependencies(repository: repository),
                onSessionExpired: {}
            )
        }
    }
#endif
