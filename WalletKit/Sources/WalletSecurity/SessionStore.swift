import Domain
import Foundation

/// The signed-in session: tokens and PIN record in secure storage, the lock state in memory.
///
/// - Supplies tokens to `WalletAPI` (`SessionTokenProvider`) and drives the auth screens
///   (`SessionManaging`).
/// - An actor, so state, tokens and the PIN attempt counter can't race. Where it awaits
///   (network, PIN hashing, Face ID), `generation` detects a sign-out or new login in the
///   meantime and the late result is dropped.
/// - Nothing here is ever logged; `SessionTokens` redacts itself.
public actor SessionStore: SessionManaging, SessionTokenProvider {
    enum Key {
        static let tokens = "session.tokens"
        static let pin = "session.pin"
    }

    private let api: any AuthAPI
    private let store: any SecureStore
    private let biometrics: any BiometricAuthenticator
    private let hasher: PINHasher
    private var state: SessionState = .signedOut {
        didSet {
            if state != oldValue {
                for listener in listeners.values {
                    listener.yield(state)
                }
            }
        }
    }
    /// Everyone following `stateUpdates()`.
    private var listeners: [UUID: AsyncStream<SessionState>.Continuation] = [:]
    private var tokens: SessionTokens?
    /// Bumped by every wipe and login.
    private var generation = 0

    public init(api: any AuthAPI, store: any SecureStore, biometrics: any BiometricAuthenticator) {
        self.init(api: api, store: store, biometrics: biometrics, hasher: PINHasher())
    }

    /// Tests pass a cheap hasher; the iteration count is stored with each record.
    init(api: any AuthAPI, store: any SecureStore, biometrics: any BiometricAuthenticator, hasher: PINHasher) {
        self.api = api
        self.store = store
        self.biometrics = biometrics
        self.hasher = hasher
    }

    // MARK: - SessionManaging

    /// Tokens and a PIN with attempts left: locked. Missing or corrupt data is wiped:
    /// tokens without a PIN mean the app quit during PIN creation, and asking for a new PIN
    /// then would let whoever holds the phone take over the session without the password.
    /// If the Keychain can't be read at all (the app launched while the phone was locked),
    /// nothing is deleted: the screen shows "locked" and unlocking reads it again.
    public func restore() async -> SessionState {
        do {
            let stored = try loadTokens()
            let record = try loadPIN()
            guard let stored, let record, record.attemptsLeft > 0 else {
                wipe()
                return state
            }
            tokens = stored
        } catch is SecureStoreError {
            tokens = nil
        } catch {
            wipe()
            return state
        }
        state = .locked
        return state
    }

    public func currentState() async -> SessionState {
        state
    }

    /// Always starts a fresh session: any earlier tokens and PIN are wiped first.
    public func login(email: String, password: String) async throws(AuthError) -> SessionState {
        wipe()
        let started = generation
        let issued = try await api.login(email: email, password: password)
        // Another sign-in or a sign-out happened while this one was on the network.
        guard started == generation else {
            throw .cancelled
        }
        try save(issued)
        tokens = issued
        state = .needsPIN
        return state
    }

    public func createPIN(_ pin: String) async throws(AuthError) -> SessionState {
        guard state == .needsPIN else {
            return state
        }
        guard Self.isValidPIN(pin) else {
            throw .invalidPIN
        }
        let started = generation
        var record = try await makeRecord(pin)
        guard started == generation, state == .needsPIN else {
            return state
        }
        record.biometricState = biometrics.enrollmentState()
        try savePIN(record)
        state = .unlocked
        return state
    }

    /// The attempt is counted and saved before the PIN is checked, so a failed write or a
    /// killed app never yields a free guess. Five wrong PINs wipe the session (ADR-019).
    public func unlock(pin: String) async throws(AuthError) -> SessionState {
        guard state == .locked else {
            return state
        }
        guard var record = try loadSession() else {
            return state
        }
        record.attemptsLeft -= 1
        try savePIN(record)
        let started = generation
        let matches = Self.isValidPIN(pin) ? try await verify(pin, against: record) : false
        guard started == generation, state == .locked else {
            return state
        }
        if matches {
            record.attemptsLeft = PINRecord.maxAttempts
            // The PIN proves it's the owner, so the current Face ID enrolment is accepted.
            record.biometricState = biometrics.enrollmentState()
            // Unlocking doesn't depend on this write; if it fails, the count stays lower.
            try? savePIN(record)
            state = .unlocked
            return state
        }
        guard record.attemptsLeft > 0 else {
            wipe()
            throw .tooManyAttempts
        }
        throw .wrongPIN(attemptsLeft: record.attemptsLeft)
    }

    /// Refused if the enrolled faces or fingers changed since the PIN was last entered.
    public func unlockWithBiometrics(reason: String) async throws(AuthError) -> SessionState {
        guard state == .locked else {
            return state
        }
        guard var record = try loadSession() else {
            return state
        }
        guard let expected = record.biometricState, expected == biometrics.enrollmentState() else {
            throw .biometryChanged
        }
        let started = generation
        let authenticated = try await biometrics.authenticate(reason: reason)
        // The user may have signed out while the system prompt was up.
        guard started == generation, state == .locked else {
            return state
        }
        guard authenticated == expected else {
            throw .biometryChanged
        }
        if record.attemptsLeft != PINRecord.maxAttempts {
            record.attemptsLeft = PINRecord.maxAttempts
            try? savePIN(record)
        }
        state = .unlocked
        return state
    }

    /// Only when Face ID is set up and its enrolment matches the one saved with the PIN.
    public func canUseBiometrics() async -> Bool {
        guard biometrics.isAvailable(), let record = try? loadPIN(), let expected = record.biometricState else {
            return false
        }
        return expected == biometrics.enrollmentState()
    }

    public func lock() async -> SessionState {
        if state == .unlocked {
            state = .locked
        }
        return state
    }

    public func signOut() async -> SessionState {
        wipe()
        return state
    }

    // MARK: - SessionTokenProvider

    /// The token in any signed-in state, including locked: Phase 6's outbox may finish a
    /// pending transfer while the screen is locked. The UI shows nothing until unlocked.
    public func accessToken() async -> String? {
        tokens?.accessToken
    }

    /// Called by `AuthInterceptor` on a 401, once at a time. A refused refresh token ends
    /// the session (`SessionRefreshError`); being offline doesn't (ADR-012).
    public func refreshAccessToken() async throws -> String {
        guard let refreshToken = tokens?.refreshToken else {
            throw SessionRefreshError.noSession
        }
        let started = generation
        let issued: SessionTokens
        do throws(AuthError) {
            issued = try await api.refresh(refreshToken: refreshToken)
        } catch .sessionExpired {
            if started == generation {
                wipe()
            }
            throw SessionRefreshError.rejected
        }
        // Signed out, or someone else signed in, while this was on the network: these tokens
        // belong to a session that no longer exists and must not be kept.
        guard started == generation, tokens?.refreshToken == refreshToken else {
            throw SessionRefreshError.noSession
        }
        // The old refresh token no longer works, so the new pair is kept in memory even if
        // the Keychain write fails; it is then only lost when the app quits.
        tokens = issued
        try? save(issued)
        return issued.accessToken
    }

    // MARK: - Helpers

    /// Six ASCII digits. Checked on UTF-8 bytes: a `Character` check lets "1\u{301}" through.
    static func isValidPIN(_ pin: String) -> Bool {
        pin.utf8.count == 6
            && pin.utf8.allSatisfy {
                (0x30...0x39).contains($0)
            }
    }

    /// The PIN record, with the tokens loaded into memory. `nil` after wiping, when the
    /// session is gone (no record, no tokens, corrupt, or no attempts left).
    private func loadSession() throws(AuthError) -> PINRecord? {
        do {
            let stored = try tokens ?? loadTokens()
            guard let stored, let record = try loadPIN(), record.attemptsLeft > 0 else {
                wipe()
                return nil
            }
            tokens = stored
            return record
        } catch is SecureStoreError {
            throw .storageUnavailable
        } catch {
            wipe()
            return nil
        }
    }

    /// PBKDF2 at 600,000 iterations takes a noticeable fraction of a second, so it runs off
    /// the actor (`nonisolated async`) and `accessToken()` isn't blocked meanwhile.
    private nonisolated func makeRecord(_ pin: String) async throws(AuthError) -> PINRecord {
        do {
            return try hasher.makeRecord(for: pin)
        } catch {
            throw .storageUnavailable
        }
    }

    private nonisolated func verify(_ pin: String, against record: PINRecord) async throws(AuthError) -> Bool {
        do {
            return try hasher.verify(pin, against: record)
        } catch {
            throw .storageUnavailable
        }
    }

    private func loadTokens() throws -> SessionTokens? {
        guard let data = try store.data(for: Key.tokens) else {
            return nil
        }
        let stored = try JSONDecoder().decode(StoredTokens.self, from: data)
        return SessionTokens(accessToken: stored.accessToken, refreshToken: stored.refreshToken)
    }

    private func save(_ tokens: SessionTokens) throws(AuthError) {
        do {
            let stored = StoredTokens(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken)
            try store.set(try JSONEncoder().encode(stored), for: Key.tokens)
        } catch {
            throw .storageUnavailable
        }
    }

    private func loadPIN() throws -> PINRecord? {
        guard let data = try store.data(for: Key.pin) else {
            return nil
        }
        return try JSONDecoder().decode(PINRecord.self, from: data)
    }

    private func savePIN(_ record: PINRecord) throws(AuthError) {
        do {
            try store.set(try JSONEncoder().encode(record), for: Key.pin)
        } catch {
            throw .storageUnavailable
        }
    }

    /// Signed out in memory first, so a failed delete can never leave the app unlocked.
    /// A PIN record that survives a failed delete has `attemptsLeft == 0` or no tokens, and
    /// is wiped again at the next launch.
    ///
    /// Then the server is asked to revoke the tokens: on sign-out, after too many wrong PINs,
    /// and for a session left by an earlier install. It runs on its own task, so signing out
    /// never waits on the network; if it fails, the tokens still expire on the server.
    private func wipe() {
        let refreshToken = tokens?.refreshToken ?? (try? loadTokens())?.refreshToken
        generation += 1
        tokens = nil
        state = .signedOut
        try? store.remove(Key.tokens)
        try? store.remove(Key.pin)
        if let refreshToken {
            Task { [api] in
                try? await api.logout(refreshToken: refreshToken)
            }
        }
    }
}

// MARK: - State updates

extension SessionStore {
    /// Only the newest state is buffered: a listener that falls behind needs where the
    /// session is now, not every step on the way.
    public func stateUpdates() async -> AsyncStream<SessionState> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: SessionState.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let id = UUID()
        listeners[id] = continuation
        continuation.yield(state)
        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.removeListener(id)
            }
        }
        return stream
    }

    private func removeListener(_ id: UUID) {
        listeners[id] = nil
    }
}

/// The Keychain format for the tokens. Kept apart from `SessionTokens` so changing the
/// Domain type can't silently change what's stored.
private struct StoredTokens: Codable {
    let accessToken: String
    let refreshToken: String
}
