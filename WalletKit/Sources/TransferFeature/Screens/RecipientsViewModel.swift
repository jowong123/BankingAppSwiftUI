import Domain
import Observation

/// Saved payees the money can go to: those in a different currency from the account,
/// since a transfer converts (the quote route refuses the same currency).
@Observable @MainActor
final class RecipientsViewModel {
    struct State: Equatable {
        var recipients: [Recipient] = []
        var isLoading = false
        var hasLoaded = false
        var error: UserFacingError?

        var showsEmpty: Bool {
            hasLoaded && recipients.isEmpty && error == nil
        }
    }

    private(set) var state = State()
    private let source: Account
    private let repository: any TransfersRepository
    private let signer: any TransferSigning
    private let router: TransferRouter
    private let onSessionExpired: @MainActor () -> Void

    init(
        source: Account,
        dependencies: TransferDependencies,
        router: TransferRouter,
        onSessionExpired: @escaping @MainActor () -> Void
    ) {
        self.source = source
        self.repository = dependencies.repository
        self.signer = dependencies.signer
        self.router = router
        self.onSessionExpired = onSessionExpired
    }

    /// A device that can't approve transfers says so first, before the user picks anyone.
    func onAppear() async {
        guard !state.hasLoaded else {
            return
        }
        let availability = await signer.availability()
        guard availability == .ready else {
            router.showSigningIssue(availability)
            return
        }
        await load()
    }

    func retry() async {
        await load()
    }

    func select(_ recipient: Recipient) {
        router.push(.amount(recipient))
    }

    private func load() async {
        guard !state.isLoading else {
            return
        }
        state.isLoading = true
        defer {
            state.isLoading = false
        }
        do throws(TransferError) {
            state.recipients = try await repository.recipients().filter {
                $0.currency != source.currency
            }
            state.hasLoaded = true
            state.error = nil
        } catch {
            if error == .sessionExpired {
                onSessionExpired()
            }
            if let shown = TransferMessages.userFacing(error) {
                state.error = shown
            }
        }
    }
}
