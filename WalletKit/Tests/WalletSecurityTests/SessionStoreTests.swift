import Domain
import Foundation
import Testing

@testable import WalletSecurity

@Suite struct SessionStoreTests {
    @Test func loginThenCreatePINUnlocks() async throws {
        let storage = InMemoryStore()
        let store = makeStore(storage: storage)

        #expect(try await store.login(email: "demo@wallet.test", password: "pw") == .needsPIN)
        #expect(try await store.createPIN("123456") == .unlocked)
        #expect(await store.accessToken() == "a1")
        #expect(storage.keys == [SessionStore.Key.tokens, SessionStore.Key.pin])
    }

    @Test func wrongCredentialsLeaveNothingStored() async {
        let api = FakeAuthAPI()
        await api.setLogin(.failure(.invalidCredentials))
        let storage = InMemoryStore()
        let store = makeStore(api: api, storage: storage)

        await #expect(throws: AuthError.invalidCredentials) {
            try await store.login(email: "demo@wallet.test", password: "bad")
        }
        #expect(await store.currentState() == .signedOut)
        #expect(storage.keys.isEmpty)
    }

    @Test(arguments: ["12345", "1234567", "12345a", "", "１２３４５６", "1\u{301}23456", "5\u{20E3}23456"])
    func pinMustBeSixASCIIDigits(pin: String) async throws {
        let store = makeStore()
        _ = try await store.login(email: "demo@wallet.test", password: "pw")

        await #expect(throws: AuthError.invalidPIN) {
            try await store.createPIN(pin)
        }
        #expect(await store.currentState() == .needsPIN)
    }

    @Test func tokensAreStoredButNeverAsPlainPIN() async throws {
        let storage = InMemoryStore()
        _ = try await lockedStore(storage: storage)

        let pinRecord = try #require(storage.raw(SessionStore.Key.pin))
        #expect(!(String(bytes: pinRecord, encoding: .utf8) ?? "").contains("123456"))
    }

    // MARK: Restore

    @Test func relaunchWithTokensAndPINStartsLocked() async throws {
        let storage = InMemoryStore()
        _ = try await lockedStore(storage: storage)

        let relaunched = makeStore(storage: storage)

        #expect(await relaunched.restore() == .locked)
        #expect(await relaunched.accessToken() == "a1")
    }

    /// Quitting during PIN creation must not let someone else set a PIN on the session.
    @Test func relaunchWithTokensButNoPINSignsOutAndWipes() async throws {
        let storage = InMemoryStore()
        let store = makeStore(storage: storage)
        _ = try await store.login(email: "demo@wallet.test", password: "pw")

        let relaunched = makeStore(storage: storage)

        #expect(await relaunched.restore() == .signedOut)
        #expect(storage.keys.isEmpty)
    }

    @Test func relaunchWithNothingIsSignedOut() async {
        #expect(await makeStore().restore() == .signedOut)
    }

    // MARK: Unlock

    @Test func rightPINUnlocks() async throws {
        let store = try await lockedStore()

        #expect(try await store.unlock(pin: "123456") == .unlocked)
    }

    @Test func wrongPINCountsDownThenWipesTheSession() async throws {
        let storage = InMemoryStore()
        let store = try await lockedStore(storage: storage)

        for attemptsLeft in [4, 3, 2, 1] {
            await #expect(throws: AuthError.wrongPIN(attemptsLeft: attemptsLeft)) {
                try await store.unlock(pin: "000000")
            }
        }
        await #expect(throws: AuthError.tooManyAttempts) {
            try await store.unlock(pin: "000000")
        }

        #expect(await store.currentState() == .signedOut)
        #expect(await store.accessToken() == nil)
        #expect(storage.keys.isEmpty)
    }

    /// Quitting and relaunching doesn't reset the counter.
    @Test func attemptCountSurvivesARelaunch() async throws {
        let storage = InMemoryStore()
        let store = try await lockedStore(storage: storage)
        for _ in 0..<3 {
            _ = try? await store.unlock(pin: "000000")
        }

        let relaunched = makeStore(storage: storage)
        _ = await relaunched.restore()

        await #expect(throws: AuthError.wrongPIN(attemptsLeft: 1)) {
            try await relaunched.unlock(pin: "000000")
        }
    }

    @Test func rightPINResetsTheCounter() async throws {
        let store = try await lockedStore()
        _ = try? await store.unlock(pin: "000000")
        _ = try await store.unlock(pin: "123456")
        _ = await store.lock()

        await #expect(throws: AuthError.wrongPIN(attemptsLeft: 4)) {
            try await store.unlock(pin: "000000")
        }
    }

    @Test func faceIDUnlocks() async throws {
        let store = try await lockedStore()

        #expect(try await store.unlockWithBiometrics(reason: "Unlock") == .unlocked)
    }

    @Test func failedFaceIDStaysLocked() async throws {
        let biometrics = FakeBiometrics()
        let store = try await lockedStore(biometrics: biometrics)
        biometrics.setResult(.failure(.biometryFailed))

        await #expect(throws: AuthError.biometryFailed) {
            try await store.unlockWithBiometrics(reason: "Unlock")
        }
        #expect(await store.currentState() == .locked)
    }

    @Test func lockedStoreCannotBeUnlockedByCreatingANewPIN() async throws {
        let store = try await lockedStore()

        #expect(try await store.createPIN("999999") == .locked)
        await #expect(throws: AuthError.wrongPIN(attemptsLeft: 4)) {
            try await store.unlock(pin: "999999")
        }
    }

    @Test func storageFailureWhileUnlockingIsReportedNotTreatedAsAWrongPIN() async throws {
        let storage = InMemoryStore()
        let store = try await lockedStore(storage: storage)
        storage.fail(reads: true)

        await #expect(throws: AuthError.storageUnavailable) {
            try await store.unlock(pin: "000000")
        }
        storage.fail()
        await #expect(throws: AuthError.wrongPIN(attemptsLeft: 4)) {
            try await store.unlock(pin: "000000")
        }
    }

    @Test func signOutWipesEverything() async throws {
        let storage = InMemoryStore()
        let store = try await lockedStore(storage: storage)

        #expect(await store.signOut() == .signedOut)
        #expect(storage.keys.isEmpty)
        #expect(await store.accessToken() == nil)
    }

    // MARK: Refresh

    @Test func refreshRotatesAndStoresTheNewTokens() async throws {
        let api = FakeAuthAPI()
        let storage = InMemoryStore()
        let store = try await lockedStore(api: api, storage: storage)

        #expect(try await store.refreshAccessToken() == "a2")
        #expect(await api.refreshedWith == ["r1"])

        let relaunched = makeStore(storage: storage)
        _ = await relaunched.restore()
        #expect(await relaunched.accessToken() == "a2")
    }

    @Test func refusedRefreshTokenEndsTheSession() async throws {
        let api = FakeAuthAPI()
        await api.setRefresh(.failure(.sessionExpired))
        let storage = InMemoryStore()
        let store = try await lockedStore(api: api, storage: storage)

        await #expect(throws: SessionRefreshError.rejected) {
            try await store.refreshAccessToken()
        }
        #expect(await store.currentState() == .signedOut)
        #expect(storage.keys.isEmpty)
    }

    /// Losing signal must not sign the user out.
    @Test(arguments: [AuthError.offline, .unavailable])
    func refreshThatFailsForNetworkReasonsKeepsTheSession(error: AuthError) async throws {
        let api = FakeAuthAPI()
        await api.setRefresh(.failure(error))
        let store = try await lockedStore(api: api)

        await #expect(throws: error) {
            try await store.refreshAccessToken()
        }
        #expect(await store.currentState() == .locked)
        #expect(await store.accessToken() == "a1")
    }

    @Test func refreshWithoutASessionIsNoSession() async {
        await #expect(throws: SessionRefreshError.noSession) {
            try await makeStore().refreshAccessToken()
        }
    }
}
