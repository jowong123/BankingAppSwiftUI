import AuthFeature
import Domain
import Foundation
import Testing
import os

@testable import Wallet

/// A monotonic clock the test moves by hand.
@MainActor final class TestClock {
    var now = ContinuousClock.now

    func advance(_ seconds: Int) {
        now += .seconds(seconds)
    }
}

/// Records whether the first-launch wipe ran.
final class FakeFirstLaunch: FirstLaunchMarker {
    private let flags: OSAllocatedUnfairLock<(first: Bool, marked: Bool)>

    init(first: Bool) {
        flags = OSAllocatedUnfairLock(initialState: (first, false))
    }

    var marked: Bool {
        flags.withLock {
            $0.marked
        }
    }

    func setFirst(_ first: Bool) {
        flags.withLock {
            $0.first = first
        }
    }

    func isFirstLaunch() -> Bool {
        flags.withLock {
            $0.first
        }
    }

    func markLaunched() {
        flags.withLock {
            $0.marked = true
        }
    }
}

@MainActor
@Suite struct AppCoordinatorTests {
    let clock = TestClock()

    /// Mock sign-in and storage, auto-lock after 60 s.
    func makeCoordinator(firstLaunch: (any FirstLaunchMarker)? = nil) -> AppCoordinator {
        let mock = AppEnvironment.live(arguments: ["-mockServer", "-uiTesting", "-autoLockSeconds", "60"])
        let environment = AppEnvironment(
            linkedModules: mock.linkedModules,
            session: mock.session,
            accounts: mock.accounts,
            autoLock: mock.autoLock,
            firstLaunch: firstLaunch,
            resetSessionOnLaunch: false
        )
        return AppCoordinator(
            environment: environment,
            now: { [clock] in
                clock.now
            })
    }

    func signedIn(_ coordinator: AppCoordinator? = nil) async throws -> AppCoordinator {
        let coordinator = coordinator ?? makeCoordinator()
        await coordinator.start()
        let session = coordinator.authDependencies.session
        coordinator.sessionChanged(try await session.login(email: "demo@wallet.test", password: "pw"))
        coordinator.sessionChanged(try await session.createPIN("123456"))
        return coordinator
    }

    @Test func launchWithNoSessionShowsSignIn() async {
        let coordinator = makeCoordinator()

        await coordinator.start()

        #expect(coordinator.root == .signIn(nil))
    }

    @Test func signInShowsCreatePINThenAccounts() async throws {
        let coordinator = makeCoordinator()
        await coordinator.start()
        let session = coordinator.authDependencies.session

        coordinator.sessionChanged(try await session.login(email: "demo@wallet.test", password: "pw"))
        #expect(coordinator.root == .createPIN)

        coordinator.sessionChanged(try await session.createPIN("123456"))
        #expect(coordinator.root == .accounts)
    }

    @Test func locksAfterInactivity() async throws {
        let coordinator = try await signedIn()

        clock.advance(59)
        await coordinator.checkInactivity()
        #expect(coordinator.root == .accounts)

        clock.advance(1)
        await coordinator.checkInactivity()
        #expect(coordinator.root == .unlock)
    }

    @Test func touchesKeepItUnlocked() async throws {
        let coordinator = try await signedIn()

        clock.advance(50)
        coordinator.userInteracted()
        clock.advance(50)
        await coordinator.checkInactivity()

        #expect(coordinator.root == .accounts)
    }

    @Test func locksOnReturnAfterTimeInTheBackground() async throws {
        let coordinator = try await signedIn()

        coordinator.enteredBackground()
        clock.advance(60)
        await coordinator.becameActive()

        #expect(coordinator.root == .unlock)
    }

    @Test func shortTripToTheBackgroundStaysUnlocked() async throws {
        let coordinator = try await signedIn()

        coordinator.enteredBackground()
        clock.advance(10)
        await coordinator.becameActive()

        #expect(coordinator.root == .accounts)
    }

    /// Idle before leaving plus time away both count as time without use.
    @Test func idleTimeBeforeLeavingCountsOnReturn() async throws {
        let coordinator = try await signedIn()

        clock.advance(40)
        coordinator.enteredBackground()
        clock.advance(25)
        await coordinator.becameActive()

        #expect(coordinator.root == .unlock)
    }

    /// The cover stays up from going to the background until the lock decision is made.
    @Test func coverStaysUpUntilTheLockDecision() async throws {
        let coordinator = try await signedIn()

        coordinator.enteredBackground()
        #expect(coordinator.needsLockCheck)

        clock.advance(60)
        await coordinator.becameActive()

        #expect(!coordinator.needsLockCheck)
        #expect(coordinator.root == .unlock)
    }

    /// Nobody can pick up a phone left on "create PIN" and choose the PIN.
    @Test func unfinishedPINSetupTimesOutToSignedOut() async throws {
        let coordinator = makeCoordinator()
        await coordinator.start()
        let session = coordinator.authDependencies.session
        coordinator.sessionChanged(try await session.login(email: "demo@wallet.test", password: "pw"))

        clock.advance(60)
        await coordinator.checkInactivity()

        #expect(coordinator.root == .signIn(nil))
        #expect(await session.currentState() == .signedOut)
    }

    @Test func expiredSessionSignsOutWithANotice() async throws {
        let coordinator = try await signedIn()

        coordinator.sessionExpired()
        for _ in 0..<100 where coordinator.root == .accounts {
            await Task.yield()
        }

        #expect(coordinator.root == .signIn(.sessionExpired))
        #expect(await coordinator.authDependencies.session.currentState() == .signedOut)
    }

    /// iOS keeps Keychain items across a delete and reinstall; a fresh install wipes them.
    @Test func firstLaunchWipesASessionLeftByAnEarlierInstall() async throws {
        let marker = FakeFirstLaunch(first: false)
        let coordinator = try await signedIn(makeCoordinator(firstLaunch: marker))
        _ = await coordinator.authDependencies.session.lock()

        marker.setFirst(true)
        await coordinator.start()

        #expect(coordinator.root == .signIn(nil))
        #expect(marker.marked)
    }
}
