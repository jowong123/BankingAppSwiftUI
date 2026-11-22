import Domain
import Foundation
import Testing

@testable import WalletSecurity

/// `stateUpdates()` reports changes nobody asked for, so the app can react to a session
/// that ended in the background (SPEC section 10, Phase 5 carry-over). The time limit turns
/// a missing update into a failure rather than a test waiting forever.
@Suite(.timeLimit(.minutes(1))) struct SessionStateUpdatesTests {
    @Test func startsWithTheCurrentStateThenFollowsChanges() async throws {
        let store = try await lockedStore()
        var updates = await store.stateUpdates().makeAsyncIterator()

        #expect(await updates.next() == .locked)
        _ = try await store.unlock(pin: "123456")
        #expect(await updates.next() == .unlocked)
        _ = await store.signOut()
        #expect(await updates.next() == .signedOut)
    }

    /// The case the app can't see otherwise: a background call's refresh is refused.
    @Test func refusedRefreshInTheBackgroundIsReported() async throws {
        let api = FakeAuthAPI()
        await api.setRefresh(.failure(.sessionExpired))
        let store = try await lockedStore(api: api)
        _ = try await store.unlock(pin: "123456")
        var updates = await store.stateUpdates().makeAsyncIterator()
        #expect(await updates.next() == .unlocked)

        _ = try? await store.refreshAccessToken()

        #expect(await updates.next() == .signedOut)
    }

    @Test func everyListenerHearsTheChange() async throws {
        let store = try await lockedStore()
        var first = await store.stateUpdates().makeAsyncIterator()
        var second = await store.stateUpdates().makeAsyncIterator()
        _ = await first.next()
        _ = await second.next()

        _ = await store.signOut()

        #expect(await first.next() == .signedOut)
        #expect(await second.next() == .signedOut)
    }
}
