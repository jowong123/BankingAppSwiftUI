import Domain
import Observation

/// Email and password. A successful sign-in reports `.needsPIN`; the coordinator then
/// shows "create PIN".
@Observable @MainActor
final class SignInViewModel {
    struct State: Equatable {
        var email = ""
        var hasPassword = false
        var isSubmitting = false
        var notice: String?
        var error: UserFacingError?

        var canSubmit: Bool {
            !email.trimmingCharacters(in: .whitespaces).isEmpty && hasPassword && !isSubmitting
        }
    }

    private(set) var state = State()
    /// Kept out of `State`, so it never appears in a state dump or a test failure message.
    private(set) var password = ""
    private let session: any SessionManaging
    private let onSessionChange: @MainActor (SessionState) -> Void

    init(
        notice: SignInNotice?,
        dependencies: AuthDependencies,
        onSessionChange: @escaping @MainActor (SessionState) -> Void
    ) {
        self.session = dependencies.session
        self.onSessionChange = onSessionChange
        if notice == .sessionExpired {
            state.notice = AuthStrings.sessionExpired
        }
    }

    func setEmail(_ email: String) {
        state.email = email
        state.error = nil
    }

    func setPassword(_ password: String) {
        self.password = password
        state.hasPassword = !password.isEmpty
        state.error = nil
    }

    func submit() async {
        guard state.canSubmit else {
            return
        }
        state.isSubmitting = true
        defer {
            state.isSubmitting = false
        }
        do throws(AuthError) {
            let next = try await session.login(
                email: state.email.trimmingCharacters(in: .whitespaces),
                password: password
            )
            // The password isn't needed again; don't keep it in memory.
            setPassword("")
            state.notice = nil
            onSessionChange(next)
        } catch {
            if error == .invalidCredentials {
                setPassword("")
            }
            state.error = AuthMessages.userFacing(error)
        }
    }
}
