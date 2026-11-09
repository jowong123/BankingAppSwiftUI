import Domain

@testable import AuthFeature

/// Scripted `SessionManaging`. Records the calls the screens make.
actor FakeSession: SessionManaging {
    var loginResult: Result<SessionState, AuthError> = .success(.needsPIN)
    var createPINResult: Result<SessionState, AuthError> = .success(.unlocked)
    var unlockResult: Result<SessionState, AuthError> = .success(.unlocked)
    var biometricsResult: Result<SessionState, AuthError> = .success(.unlocked)
    var biometricsAvailable = true
    private(set) var calls: [String] = []
    private(set) var createdPIN: String?

    func set(login: Result<SessionState, AuthError>) {
        loginResult = login
    }
    func set(createPIN: Result<SessionState, AuthError>) {
        createPINResult = createPIN
    }
    func set(unlock: Result<SessionState, AuthError>) {
        unlockResult = unlock
    }
    func set(biometrics: Result<SessionState, AuthError>, available: Bool = true) {
        biometricsResult = biometrics
        biometricsAvailable = available
    }

    func restore() async -> SessionState {
        .signedOut
    }
    func currentState() async -> SessionState {
        .signedOut
    }
    func login(email: String, password: String) async throws(AuthError) -> SessionState {
        calls.append("login")
        return try loginResult.get()
    }
    func createPIN(_ pin: String) async throws(AuthError) -> SessionState {
        calls.append("createPIN")
        createdPIN = pin
        return try createPINResult.get()
    }
    func unlock(pin: String) async throws(AuthError) -> SessionState {
        calls.append("unlock")
        return try unlockResult.get()
    }
    func unlockWithBiometrics(reason: String) async throws(AuthError) -> SessionState {
        calls.append("biometrics")
        return try biometricsResult.get()
    }
    func canUseBiometrics() async -> Bool {
        biometricsAvailable
    }
    func lock() async -> SessionState {
        .locked
    }
    func signOut() async -> SessionState {
        calls.append("signOut")
        return .signedOut
    }
}

/// Collects what a screen reports through `onSessionChange`.
@MainActor final class SessionChanges {
    private(set) var states: [SessionState] = []

    func record(_ state: SessionState) {
        states.append(state)
    }
}
