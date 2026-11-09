import Domain
import Observation

/// Face ID first when it's available, the PIN otherwise. Five wrong PINs sign out.
@Observable @MainActor
final class UnlockViewModel {
    struct State: Equatable {
        var canUseBiometrics = false
        var isChecking = false
        var error: UserFacingError?
        /// The last attempt failed: explain, then sign out when the user taps OK.
        var showsTooManyAttempts = false
    }

    private(set) var state = State()
    private let session: any SessionManaging
    private let onSessionChange: @MainActor (SessionState) -> Void
    private var hasAppeared = false

    init(dependencies: AuthDependencies, onSessionChange: @escaping @MainActor (SessionState) -> Void) {
        self.session = dependencies.session
        self.onSessionChange = onSessionChange
    }

    /// Offers Face ID straight away, once.
    func onAppear() async {
        guard !hasAppeared else {
            return
        }
        hasAppeared = true
        state.canUseBiometrics = await session.canUseBiometrics()
        if state.canUseBiometrics {
            await unlockWithBiometrics()
        }
    }

    func unlockWithBiometrics() async {
        guard !state.isChecking else {
            return
        }
        state.isChecking = true
        defer {
            state.isChecking = false
        }
        do throws(AuthError) {
            onSessionChange(try await session.unlockWithBiometrics(reason: AuthStrings.biometricReason))
        } catch {
            state.error = AuthMessages.userFacing(error) ?? state.error
        }
    }

    /// Called by the PIN pad with all six digits.
    func entered(_ pin: String) async {
        guard !state.isChecking, !state.showsTooManyAttempts else {
            return
        }
        state.isChecking = true
        defer {
            state.isChecking = false
        }
        do throws(AuthError) {
            onSessionChange(try await session.unlock(pin: pin))
        } catch {
            if error == .tooManyAttempts {
                state.error = nil
                state.showsTooManyAttempts = true
            } else {
                state.error = AuthMessages.userFacing(error)
            }
        }
    }

    /// After the "too many wrong PINs" alert. The session is already wiped.
    func acknowledgeSignedOut() {
        state.showsTooManyAttempts = false
        onSessionChange(.signedOut)
    }

    func signOut() async {
        onSessionChange(await session.signOut())
    }
}
