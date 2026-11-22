import Domain
import Observation

/// How much to send, in the account's currency. Continue asks for a quote, so a refused
/// amount (below the fee, above the limit) is caught here rather than on the review.
@Observable @MainActor
final class AmountViewModel {
    struct State: Equatable {
        var amount: Money?
        var isQuoting = false
        var exceedsBalance = false
        var error: UserFacingError?

        var canContinue: Bool {
            guard let amount else {
                return false
            }
            return !amount.isZero && !amount.isNegative && !exceedsBalance && !isQuoting
        }
    }

    private(set) var state = State()
    let source: Account
    let recipient: Recipient
    private let repository: any TransfersRepository
    private let router: TransferRouter
    private let onSessionExpired: @MainActor () -> Void

    init(
        source: Account,
        recipient: Recipient,
        dependencies: TransferDependencies,
        router: TransferRouter,
        onSessionExpired: @escaping @MainActor () -> Void
    ) {
        self.source = source
        self.recipient = recipient
        self.repository = dependencies.repository
        self.router = router
        self.onSessionExpired = onSessionExpired
    }

    func setAmount(_ amount: Money?) {
        state.amount = amount
        state.error = nil
        state.exceedsBalance =
            amount.map {
                (try? $0.compare(to: source.balance)) == .orderedDescending
            } ?? false
    }

    func continueTapped() async {
        guard state.canContinue, let amount = state.amount else {
            return
        }
        state.isQuoting = true
        defer {
            state.isQuoting = false
        }
        do throws(TransferError) {
            let quote = try await repository.quote(sourceAmount: amount, targetCurrency: recipient.currency)
            state.error = nil
            router.push(.review(recipient, quote))
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
