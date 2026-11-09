import Domain
import Foundation
import Testing

@testable import WalletSecurity

/// Locked-phone launches, attempt counting under failure, races with sign-out, and
/// Face ID enrolment changes (Phase 5 security review, ADR-019).
@Suite struct SessionStoreHardeningTests {
    /// Launched while the phone is locked: the Keychain can't be read, and nothing is deleted.
    @Test func unreadableKeychainAtLaunchKeepsTheSessionAndUnlocksLater() async throws {
        let storage = InMemoryStore()
        _ = try await lockedStore(storage: storage)
        storage.fail(reads: true)
        let relaunched = makeStore(storage: storage)

        #expect(await relaunched.restore() == .locked)
        #expect(storage.keys == [SessionStore.Key.tokens, SessionStore.Key.pin])

        storage.fail()
        #expect(try await relaunched.unlock(pin: "123456") == .unlocked)
        #expect(await relaunched.accessToken() == "a1")
    }

    @Test func corruptRecordAtLaunchIsWiped() async throws {
        let storage = InMemoryStore()
        _ = try await lockedStore(storage: storage)
        try storage.set(Data("not json".utf8), for: SessionStore.Key.pin)

        #expect(await makeStore(storage: storage).restore() == .signedOut)
        #expect(storage.keys.isEmpty)
    }

    /// If the failed attempt can't be saved, the PIN isn't checked at all: neither a wrong
    /// nor a right PIN gives a different answer, so the error can't be used to guess.
    @Test func attemptIsSavedBeforeThePINIsChecked() async throws {
        let storage = InMemoryStore()
        let store = try await lockedStore(storage: storage)
        storage.fail(writes: true)

        await #expect(throws: AuthError.storageUnavailable) {
            try await store.unlock(pin: "000000")
        }
        await #expect(throws: AuthError.storageUnavailable) {
            try await store.unlock(pin: "123456")
        }
        #expect(await store.currentState() == .locked)
    }

    /// The last wrong PIN is saved as zero attempts first, so a wipe that fails still
    /// can't give the next launch another guess.
    @Test func failedWipeAfterTheLastAttemptStillSignsOutAtNextLaunch() async throws {
        let storage = InMemoryStore()
        let store = try await lockedStore(storage: storage)
        for _ in 0..<4 {
            _ = try? await store.unlock(pin: "000000")
        }
        storage.fail(deletes: true)
        await #expect(throws: AuthError.tooManyAttempts) {
            try await store.unlock(pin: "000000")
        }
        #expect(!storage.keys.isEmpty)

        storage.fail()
        let relaunched = makeStore(storage: storage)

        #expect(await relaunched.restore() == .signedOut)
        #expect(storage.keys.isEmpty)
    }

    @Test func concurrentWrongPINsAreAllCounted() async throws {
        let store = try await lockedStore()

        async let first = attemptsLeft(after: "000000", on: store)
        async let second = attemptsLeft(after: "111111", on: store)

        #expect(Set(await [first, second]) == [4, 3])
    }

    /// The attempts left reported for a wrong PIN, or nil for any other outcome.
    private func attemptsLeft(after pin: String, on store: SessionStore) async -> Int? {
        do {
            _ = try await store.unlock(pin: pin)
            return nil
        } catch {
            if case .wrongPIN(let attemptsLeft) = error {
                return attemptsLeft
            }
            return nil
        }
    }

    /// Signing out while a refresh is on the network: the late tokens are thrown away.
    @Test func refreshThatFinishesAfterSignOutIsDropped() async throws {
        let api = FakeAuthAPI()
        let gate = Gate()
        await api.setRefresh(.success(SessionTokens(accessToken: "a2", refreshToken: "r2")), gate: gate)
        let storage = InMemoryStore()
        let store = try await lockedStore(api: api, storage: storage)

        let refresh = Task {
            try await store.refreshAccessToken()
        }
        while await api.refreshedWith.isEmpty {
            await Task.yield()
        }
        _ = await store.signOut()
        await gate.open()

        await #expect(throws: SessionRefreshError.noSession) {
            try await refresh.value
        }
        #expect(await store.accessToken() == nil)
        #expect(storage.keys.isEmpty)
    }

    /// Someone else signs in while the old session's refresh is in flight: their session stays.
    @Test func refreshFromAnOldSessionNeverReplacesANewOne() async throws {
        let api = FakeAuthAPI()
        let gate = Gate()
        await api.setRefresh(.success(SessionTokens(accessToken: "old-a2", refreshToken: "old-r2")), gate: gate)
        let store = try await lockedStore(api: api)

        let refresh = Task {
            try await store.refreshAccessToken()
        }
        while await api.refreshedWith.isEmpty {
            await Task.yield()
        }
        await api.setLogin(.success(SessionTokens(accessToken: "b1", refreshToken: "rb1")))
        _ = try await store.login(email: "b@wallet.test", password: "pw")
        await gate.open()

        await #expect(throws: SessionRefreshError.noSession) {
            try await refresh.value
        }
        #expect(await store.accessToken() == "b1")
    }

    /// Someone who knows the phone's passcode adds their face: Face ID is refused until the PIN.
    @Test func newFaceEnrolmentTurnsFaceIDOffUntilThePINIsEntered() async throws {
        let biometrics = FakeBiometrics()
        let store = try await lockedStore(biometrics: biometrics)
        #expect(await store.canUseBiometrics())

        biometrics.enroll("face-A+face-B")

        #expect(await !store.canUseBiometrics())
        await #expect(throws: AuthError.biometryChanged) {
            try await store.unlockWithBiometrics(reason: "Unlock")
        }
        // Refused before the prompt: the new face never even gets to try.
        #expect(biometrics.prompts == 0)

        _ = try await store.unlock(pin: "123456")
        _ = await store.lock()

        #expect(await store.canUseBiometrics())
        #expect(try await store.unlockWithBiometrics(reason: "Unlock") == .unlocked)
    }

    /// The enrolment is checked again on the context that just succeeded.
    @Test func faceIDThatSucceedsWithADifferentEnrolmentIsRefused() async throws {
        let biometrics = FakeBiometrics()
        let store = try await lockedStore(biometrics: biometrics)
        biometrics.changeDuringPrompt(to: "face-A+face-B")

        await #expect(throws: AuthError.biometryChanged) {
            try await store.unlockWithBiometrics(reason: "Unlock")
        }
        #expect(await store.currentState() == .locked)
    }

    @Test func faceIDCannotUnlockWhenThePINRecordIsGone() async throws {
        let storage = InMemoryStore()
        let store = try await lockedStore(storage: storage)
        try storage.remove(SessionStore.Key.pin)

        #expect(try await store.unlockWithBiometrics(reason: "Unlock") == .signedOut)
        #expect(storage.keys.isEmpty)
    }
}
