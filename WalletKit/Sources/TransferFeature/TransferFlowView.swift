import Domain
import SwiftUI

/// The only public view of the feature: recipient → amount → review → status.
///
/// - Parameters:
///   - source: the account the money leaves.
///   - onFinish: Cancel before sending, or Done on the status screen. A transfer already
///     sent keeps going in the outbox after the flow closes.
///   - onSessionExpired: the server says the session can't be renewed.
public struct TransferFlowView: View {
    @Bindable private var router: TransferRouter
    @State private var recipientsViewModel: RecipientsViewModel
    private let source: Account
    private let dependencies: TransferDependencies
    private let onFinish: @MainActor () -> Void
    private let onSessionExpired: @MainActor () -> Void

    public init(
        router: TransferRouter,
        dependencies: TransferDependencies,
        source: Account,
        onFinish: @escaping @MainActor () -> Void,
        onSessionExpired: @escaping @MainActor () -> Void
    ) {
        self.router = router
        self.dependencies = dependencies
        self.source = source
        self.onFinish = onFinish
        self.onSessionExpired = onSessionExpired
        _recipientsViewModel = State(
            initialValue: RecipientsViewModel(
                source: source,
                dependencies: dependencies,
                router: router,
                onSessionExpired: onSessionExpired
            ))
    }

    public var body: some View {
        NavigationStack(path: $router.path) {
            Group {
                if let sentID = router.sentTransferID {
                    StatusScreen(transferID: sentID, dependencies: dependencies, onFinish: onFinish)
                } else {
                    RecipientsView(viewModel: recipientsViewModel)
                        .toolbar {
                            cancelButton
                        }
                }
            }
            .navigationDestination(for: TransferRoute.self) { route in
                destination(for: route)
                    .toolbar {
                        cancelButton
                    }
            }
        }
    }

    private var cancelButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(TransferStrings.cancel) {
                onFinish()
            }
            .accessibilityIdentifier("transfer.cancel")
        }
    }

    @ViewBuilder private func destination(for route: TransferRoute) -> some View {
        switch route {
        case .amount(let recipient):
            AmountScreen(
                source: source,
                recipient: recipient,
                dependencies: dependencies,
                router: router,
                onSessionExpired: onSessionExpired
            )
        case .review(let recipient, let quote):
            ReviewScreen(
                source: source,
                recipient: recipient,
                quote: quote,
                dependencies: dependencies,
                router: router,
                onSessionExpired: onSessionExpired
            )
        }
    }
}

/// Each screen wrapper owns its view model for as long as the screen is on the stack.
private struct AmountScreen: View {
    @State private var viewModel: AmountViewModel

    init(
        source: Account,
        recipient: Recipient,
        dependencies: TransferDependencies,
        router: TransferRouter,
        onSessionExpired: @escaping @MainActor () -> Void
    ) {
        _viewModel = State(
            initialValue: AmountViewModel(
                source: source,
                recipient: recipient,
                dependencies: dependencies,
                router: router,
                onSessionExpired: onSessionExpired
            ))
    }

    var body: some View {
        AmountView(viewModel: viewModel)
    }
}

private struct ReviewScreen: View {
    @State private var viewModel: ReviewViewModel

    init(
        source: Account,
        recipient: Recipient,
        quote: FXQuote,
        dependencies: TransferDependencies,
        router: TransferRouter,
        onSessionExpired: @escaping @MainActor () -> Void
    ) {
        _viewModel = State(
            initialValue: ReviewViewModel(
                source: source,
                recipient: recipient,
                quote: quote,
                dependencies: dependencies,
                router: router,
                onSessionExpired: onSessionExpired
            ))
    }

    var body: some View {
        ReviewView(viewModel: viewModel)
    }
}

private struct StatusScreen: View {
    @State private var viewModel: StatusViewModel

    init(transferID: UUID, dependencies: TransferDependencies, onFinish: @escaping @MainActor () -> Void) {
        _viewModel = State(
            initialValue: StatusViewModel(transferID: transferID, dependencies: dependencies, onFinish: onFinish))
    }

    var body: some View {
        StatusView(viewModel: viewModel)
    }
}
