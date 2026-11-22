import Domain
import Observation

/// Enter a six-digit PIN, then the same again. A mismatch starts over.
@Observable @MainActor
final class CreatePINViewModel {
    enum Step: Equatable {
        case enter
        case confirm
    }

    struct State: Equatable {
        var step = Step.enter
        var isSaving = false
        var error: UserFacingError?
    }

    private(set) var state = State()
    /// Held only between the two entries; never part of `State`, so it can't end up in a
    /// state dump or a test failure message.
    private var firstEntry: String?
    private let session: any SessionManaging
    private let onSessionChange: @MainActor (SessionState) -> Void

    init(dependencies: AuthDependencies, onSessionChange: @escaping @MainActor (SessionState) -> Void) {
        self.session = dependencies.session
        self.onSessionChange = onSessionChange
    }

    /// Called by the PIN pad with all six digits.
    func entered(_ pin: String) async {
        guard !state.isSaving else {
            return
        }
        switch state.step {
        case .enter:
            firstEntry = pin
            state.step = .confirm
            state.error = nil
        case .confirm:
            let matches = pin == firstEntry
            firstEntry = nil
            guard matches else {
                state = State(step: .enter, error: AuthMessages.pinMismatch)
                return
            }
            await save(pin)
        }
    }

    private func save(_ pin: String) async {
        state.isSaving = true
        defer {
            state.isSaving = false
        }
        do throws(AuthError) {
            onSessionChange(try await session.createPIN(pin))
        } catch {
            state.step = .enter
            state.error = AuthMessages.userFacing(error)
        }
    }
}
