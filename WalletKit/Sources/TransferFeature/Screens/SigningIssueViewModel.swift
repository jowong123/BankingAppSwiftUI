import Domain
import Observation

/// Shown instead of the flow when this device can't approve transfers: Face ID wasn't set up
/// at sign-in, or it changed since (SPEC section 6: "explain this in the UI"). The only way
/// back is signing in again, which binds a new key.
@Observable @MainActor
final class SigningIssueViewModel {
    struct State: Equatable {
        let issue: SigningAvailability
        /// A transfer is still in the outbox: signing out now would cancel it, so ask first.
        var confirmsSignOut = false

        var title: String {
            issue == .keyInvalidated ? TransferStrings.keyInvalidatedTitle : TransferStrings.biometryNotSetUpTitle
        }

        var message: String {
            issue == .keyInvalidated ? TransferStrings.keyInvalidatedMessage : TransferStrings.biometryNotSetUpMessage
        }
    }

    private(set) var state: State
    private let outbox: any TransferOutboxing
    private let onSignInAgain: @MainActor () -> Void

    init(
        issue: SigningAvailability,
        dependencies: TransferDependencies,
        onSignInAgain: @escaping @MainActor () -> Void
    ) {
        state = State(issue: issue)
        outbox = dependencies.outbox
        self.onSignInAgain = onSignInAgain
    }

    func signInAgain() async {
        guard await outbox.hasPending() else {
            onSignInAgain()
            return
        }
        state.confirmsSignOut = true
    }

    func confirmSignOut() {
        state.confirmsSignOut = false
        onSignInAgain()
    }

    func cancelSignOut() {
        state.confirmsSignOut = false
    }
}
