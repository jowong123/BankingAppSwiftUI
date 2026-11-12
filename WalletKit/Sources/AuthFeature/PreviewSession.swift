#if DEBUG
    import Domain

    /// Accepts everything, for SwiftUI previews. Not compiled into release builds.
    actor PreviewSession: SessionManaging {
        func restore() async -> SessionState {
            .signedOut
        }
        func currentState() async -> SessionState {
            .signedOut
        }
        func login(email: String, password: String) async throws(AuthError) -> SessionState {
            .needsPIN
        }
        func createPIN(_ pin: String) async throws(AuthError) -> SessionState {
            .unlocked
        }
        func unlock(pin: String) async throws(AuthError) -> SessionState {
            .unlocked
        }
        func unlockWithBiometrics(reason: String) async throws(AuthError) -> SessionState {
            .unlocked
        }
        func canUseBiometrics() async -> Bool {
            false
        }
        func lock() async -> SessionState {
            .locked
        }
        func signOut() async -> SessionState {
            .signedOut
        }
        func stateUpdates() async -> AsyncStream<SessionState> {
            AsyncStream {
                $0.yield(.signedOut)
            }
        }
    }
#endif
