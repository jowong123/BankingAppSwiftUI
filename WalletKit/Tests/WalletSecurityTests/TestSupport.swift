import Domain
import Foundation
import os

@testable import WalletSecurity

/// `SecureStore` in memory. Reads, writes and deletes can each be made to fail, like a
/// Keychain while the phone is locked or a full disk.
final class InMemoryStore: SecureStore {
    private struct Contents {
        var items: [String: Data] = [:]
        var readsFail = false
        var writesFail = false
        var deletesFail = false
    }

    private let contents = OSAllocatedUnfairLock(initialState: Contents())

    func data(for key: String) throws(SecureStoreError) -> Data? {
        let (failing, value) = contents.withLock {
            ($0.readsFail, $0.items[key])
        }
        guard !failing else {
            throw SecureStoreError(status: -25308)
        }
        return value
    }

    func set(_ data: Data, for key: String) throws(SecureStoreError) {
        let failing = contents.withLock {
            if !$0.writesFail {
                $0.items[key] = data
            }
            return $0.writesFail
        }
        guard !failing else {
            throw SecureStoreError(status: -34)
        }
    }

    func remove(_ key: String) throws(SecureStoreError) {
        let failing = contents.withLock {
            if !$0.deletesFail {
                $0.items[key] = nil
            }
            return $0.deletesFail
        }
        guard !failing else {
            throw SecureStoreError(status: -34)
        }
    }

    var keys: Set<String> {
        contents.withLock {
            Set($0.items.keys)
        }
    }

    func raw(_ key: String) -> Data? {
        contents.withLock {
            $0.items[key]
        }
    }

    func fail(reads: Bool = false, writes: Bool = false, deletes: Bool = false) {
        contents.withLock {
            $0.readsFail = reads
            $0.writesFail = writes
            $0.deletesFail = deletes
        }
    }
}

/// Suspends callers until `open()`.
actor Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
        if isOpen {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters = []
    }
}

/// Scripted `AuthAPI`. A refresh can be held at a gate so a test can sign out meanwhile.
actor FakeAuthAPI: AuthAPI {
    var loginResult: Result<SessionTokens, AuthError> = .success(SessionTokens(accessToken: "a1", refreshToken: "r1"))
    var refreshResult: Result<SessionTokens, AuthError> = .success(SessionTokens(accessToken: "a2", refreshToken: "r2"))
    private(set) var refreshedWith: [String] = []
    private var refreshGate: Gate?
    var logoutResult: Result<Void, AuthError> = .success(())
    private var logoutGate: Gate?
    /// Sign-out revokes on its own task; tests wait here for the call instead of sleeping.
    nonisolated let loggedOut: AsyncStream<String>
    private let loggedOutSink: AsyncStream<String>.Continuation

    init() {
        (loggedOut, loggedOutSink) = AsyncStream.makeStream()
    }

    func setLogout(_ result: Result<Void, AuthError>, gate: Gate? = nil) {
        logoutResult = result
        logoutGate = gate
    }

    func logout(refreshToken: String) async throws(AuthError) {
        loggedOutSink.yield(refreshToken)
        await logoutGate?.wait()
        try logoutResult.get()
    }

    func setLogin(_ result: Result<SessionTokens, AuthError>) {
        loginResult = result
    }

    func setRefresh(_ result: Result<SessionTokens, AuthError>, gate: Gate? = nil) {
        refreshResult = result
        refreshGate = gate
    }

    func login(email: String, password: String) async throws(AuthError) -> SessionTokens {
        try loginResult.get()
    }

    func refresh(refreshToken: String) async throws(AuthError) -> SessionTokens {
        refreshedWith.append(refreshToken)
        await refreshGate?.wait()
        return try refreshResult.get()
    }
}

/// Face ID whose enrolment the test can change, like a user adding a face in Settings.
final class FakeBiometrics: BiometricAuthenticator {
    private struct Setup {
        var available = true
        var enrollment = Data("face-A".utf8)
        var result: Result<Void, AuthError> = .success(())
        /// What a successful prompt reports, if different from `enrollment`.
        var promptEnrollment: Data?
        var prompts = 0
    }

    private let setup = OSAllocatedUnfairLock(initialState: Setup())

    func isAvailable() -> Bool {
        setup.withLock {
            $0.available
        }
    }

    func enrollmentState() -> Data? {
        setup.withLock {
            $0.available ? $0.enrollment : nil
        }
    }

    func authenticate(reason: String) async throws(AuthError) -> Data? {
        let (result, enrollment) = setup.withLock {
            $0.prompts += 1
            return ($0.result, $0.promptEnrollment ?? $0.enrollment)
        }
        try result.get()
        return enrollment
    }

    /// How many times the system prompt was shown.
    var prompts: Int {
        setup.withLock {
            $0.prompts
        }
    }

    func enroll(_ value: String) {
        setup.withLock {
            $0.enrollment = Data(value.utf8)
        }
    }

    func setResult(_ result: Result<Void, AuthError>) {
        setup.withLock {
            $0.result = result
        }
    }

    /// The enrolment changes between the pre-check and the prompt.
    func changeDuringPrompt(to value: String) {
        setup.withLock {
            $0.promptEnrollment = Data(value.utf8)
        }
    }

    func setAvailable(_ available: Bool) {
        setup.withLock {
            $0.available = available
        }
    }
}

/// A real hasher with few iterations, so tests stay fast. Production uses 600,000.
let fastHasher = PINHasher(iterations: 1_000)

func makeStore(
    api: FakeAuthAPI = FakeAuthAPI(),
    storage: InMemoryStore = InMemoryStore(),
    biometrics: FakeBiometrics = FakeBiometrics()
) -> SessionStore {
    SessionStore(api: api, store: storage, biometrics: biometrics, hasher: fastHasher)
}

/// Signed in with PIN 123456, then locked.
func lockedStore(
    api: FakeAuthAPI = FakeAuthAPI(),
    storage: InMemoryStore = InMemoryStore(),
    biometrics: FakeBiometrics = FakeBiometrics()
) async throws -> SessionStore {
    let store = makeStore(api: api, storage: storage, biometrics: biometrics)
    _ = try await store.login(email: "demo@wallet.test", password: "pw")
    _ = try await store.createPIN("123456")
    _ = await store.lock()
    return store
}
