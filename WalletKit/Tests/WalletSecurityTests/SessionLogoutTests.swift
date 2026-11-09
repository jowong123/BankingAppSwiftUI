import Domain
import Foundation
import Testing

@testable import WalletSecurity

/// Ending a session also revokes it on the server, without making sign-out wait on the
/// network (`POST /v1/auth/logout`). The time limit turns a missing revoke into a failure
/// rather than a test waiting forever for the call.
@Suite(.timeLimit(.minutes(1))) struct SessionLogoutTests {
    @Test func signOutAsksTheServerToRevokeTheSession() async throws {
        let api = FakeAuthAPI()
        var revoked = api.loggedOut.makeAsyncIterator()
        let store = try await lockedStore(api: api)

        #expect(await store.signOut() == .signedOut)

        #expect(await revoked.next() == "r1")
    }

    @Test func signOutDoesNotWaitForTheServer() async throws {
        let api = FakeAuthAPI()
        let gate = Gate()
        await api.setLogout(.success(()), gate: gate)
        var revoked = api.loggedOut.makeAsyncIterator()
        let storage = InMemoryStore()
        let store = try await lockedStore(api: api, storage: storage)

        // Returns while the server call is still held at the gate.
        #expect(await store.signOut() == .signedOut)
        #expect(storage.keys.isEmpty)

        #expect(await revoked.next() == "r1")
        await gate.open()
    }

    @Test func failedRevokeStillSignsOut() async throws {
        let api = FakeAuthAPI()
        await api.setLogout(.failure(.offline))
        var revoked = api.loggedOut.makeAsyncIterator()
        let storage = InMemoryStore()
        let store = try await lockedStore(api: api, storage: storage)

        #expect(await store.signOut() == .signedOut)
        #expect(await revoked.next() == "r1")

        #expect(storage.keys.isEmpty)
        #expect(await store.accessToken() == nil)
    }

    @Test func tooManyWrongPINsRevokeTheSession() async throws {
        let api = FakeAuthAPI()
        var revoked = api.loggedOut.makeAsyncIterator()
        let store = try await lockedStore(api: api)

        for _ in 1..<PINRecord.maxAttempts {
            _ = try? await store.unlock(pin: "000000")
        }
        await #expect(throws: AuthError.tooManyAttempts) {
            try await store.unlock(pin: "000000")
        }

        #expect(await revoked.next() == "r1")
    }

    /// A reinstall finds the old session in the Keychain: it is revoked, not just deleted.
    @Test func sessionLeftByAnEarlierInstallIsRevoked() async throws {
        let storage = InMemoryStore()
        _ = try await lockedStore(storage: storage)
        let api = FakeAuthAPI()
        var revoked = api.loggedOut.makeAsyncIterator()
        let reinstalled = makeStore(api: api, storage: storage)

        #expect(await reinstalled.signOut() == .signedOut)

        #expect(await revoked.next() == "r1")
        #expect(storage.keys.isEmpty)
    }
}
