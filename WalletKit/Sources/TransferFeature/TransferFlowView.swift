import Domain
import SwiftUI

/// The only public view of the feature: recipient → amount → review → status.
///
/// - Parameters:
///   - source: the account the money leaves.
///   - onFinish: Cancel before sending, or Done on the status screen. A transfer already
///     sent keeps going in the outbox after the flow closes.
///   - onSessionExpired: the server says the session can't be renewed.
///   - onSignInAgain: this device can't approve transfers (Face ID changed or not set up);
///     the user chose to sign out and sign in again, which binds a new key.
public struct TransferFlowView: View {
    @Bindable private var router: TransferRouter
    @State private var recipientsViewModel: RecipientsViewModel
    private let source: Account
    private let dependencies: TransferDependencies
    private let onFinish: @MainActor () -> Void
    private let onSessionExpired: @MainActor () -> Void
    private let onSignInAgain: @MainActor () -> Void

    public init(
        router: TransferRouter,
        dependencies: TransferDependencies,
        source: Account,
        onFinish: @escaping @MainActor () -> Void,
        onSessionExpired: @escaping @MainActor () -> Void,
        onSignInAgain: @escaping @MainActor () -> Void
    ) {
        self.router = router
        self.dependencies = dependencies
        self.source = source
        self.onFinish = onFinish
        self.onSessionExpired = onSessionExpired
        self.onSignInAgain = onSignInAgain
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
                if let issue = router.signingIssue {
                    SigningIssueScreen(
                        issue: issue, dependencies: dependencies, onClose: onFinish, onSignInAgain: onSignInAgain)
                } else if let sentID = router.sentTransferID {
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

private struct SigningIssueScreen: View {
    @State private var viewModel: SigningIssueViewModel
    private let onClose: @MainActor () -> Void

    init(
        issue: SigningAvailability,
        dependencies: TransferDependencies,
        onClose: @escaping @MainActor () -> Void,
        onSignInAgain: @escaping @MainActor () -> Void
    ) {
        _viewModel = State(
            initialValue: SigningIssueViewModel(issue: issue, dependencies: dependencies, onSignInAgain: onSignInAgain))
        self.onClose = onClose
    }

    var body: some View {
        SigningIssueView(viewModel: viewModel, onClose: onClose)
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
