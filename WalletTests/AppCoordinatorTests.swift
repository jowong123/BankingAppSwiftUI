import AuthFeature
import Domain
import Foundation
import Testing
import TransferFeature
import os

@testable import Wallet

/// A monotonic clock the test moves by hand.
@MainActor final class TestClock {
    var now = ContinuousClock.now

    func advance(_ seconds: Int) {
        now += .seconds(seconds)
    }
}

/// Records what the coordinator asks of the outbox.
actor RecordingOutbox: TransferOutboxing {
    private(set) var calls: [String] = []
    var pending = false

    func setPending(_ pending: Bool) {
        self.pending = pending
    }

    func send(_ draft: TransferDraft) async throws(TransferError) -> Transfer {
        calls.append("send")
        return Transfer(draft: draft, state: .authorised, createdAt: .now, updatedAt: .now)
    }

    func updates(for id: UUID) async -> AsyncStream<Transfer> {
        AsyncStream {
            $0.finish()
        }
    }

    func resumePending() async {
        calls.append("resume")
    }

    func hasPending() async -> Bool {
        pending
    }

    func removeAll() async {
        calls.append("removeAll")
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

    let outbox = RecordingOutbox()

    /// Mock sign-in and storage, a recording outbox, auto-lock after 60 s.
    func makeCoordinator(firstLaunch: (any FirstLaunchMarker)? = nil) -> AppCoordinator {
        let mock = AppEnvironment.live(arguments: ["-mockServer", "-uiTesting", "-autoLockSeconds", "60"])
        let environment = AppEnvironment(
            linkedModules: mock.linkedModules,
            session: mock.session,
            accounts: mock.accounts,
            transfers: TransferDependencies(repository: mock.transfers.repository, outbox: outbox),
            outbox: outbox,
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

    // MARK: - Transfers

    @Test func launchWithNoSessionDeletesTheOutbox() async {
        let coordinator = makeCoordinator()

        await coordinator.start()
        await coordinator.rootChanged()

        #expect(await outbox.calls == ["removeAll"])
    }

    /// Killed mid-transfer, relaunched: the outbox carries on (SPEC section 4, launch).
    @Test func launchWithASessionResumesPendingTransfers() async throws {
        let coordinator = try await signedIn()
        _ = await coordinator.authDependencies.session.lock()

        await coordinator.start()
        await coordinator.rootChanged()

        #expect(coordinator.root == .unlock)
        #expect(await outbox.calls.last == "resume")
    }

    /// The session ended in the background (a refused refresh): the app notices without a
    /// screen asking, shows why, and deletes the outbox.
    @Test func sessionEndingInTheBackgroundSignsOutAndDeletesTheOutbox() async throws {
        let coordinator = try await signedIn()
        let observing = Task {
            await coordinator.observeSession()
        }
        defer {
            observing.cancel()
        }

        _ = await coordinator.authDependencies.session.signOut()
        for _ in 0..<200 where coordinator.root == .accounts {
            await Task.yield()
        }

        #expect(coordinator.root == .signIn(.sessionExpired))
        await coordinator.rootChanged()
        #expect(await outbox.calls.last == "removeAll")
    }

    /// Every way to the sign-in screen deletes the outbox; signing in resumes it.
    @Test func outboxFollowsTheRoot() async throws {
        let coordinator = try await signedIn()
        await coordinator.rootChanged()
        #expect(await outbox.calls.last == "resume")

        coordinator.sessionChanged(.signedOut)
        await coordinator.rootChanged()
        #expect(await outbox.calls.last == "removeAll")
    }

    @Test func sendMoneyOpensTheFlowAndClosingItRefreshesAccounts() async throws {
        let coordinator = try await signedIn()
        let account = Account(id: "acc_sgd", balance: Money(amountMinor: 100, currency: .sgd), updatedAt: .now)

        coordinator.sendMoney(from: account)
        #expect(coordinator.transfer?.source == account)

        coordinator.transferFinished()
        #expect(coordinator.transfer == nil)
        #expect(coordinator.accountsReload == 1)
    }

    /// Locking takes the flow down with the balances; the outbox keeps the transfer going.
    @Test func lockingClosesTheTransferFlow() async throws {
        let coordinator = try await signedIn()
        coordinator.sendMoney(
            from: Account(id: "acc_sgd", balance: Money(amountMinor: 100, currency: .sgd), updatedAt: .now))
        let before = await outbox.calls

        clock.advance(60)
        await coordinator.checkInactivity()

        #expect(coordinator.root == .unlock)
        #expect(coordinator.transfer == nil)
        #expect(await outbox.calls == before)
    }

    @Test func signOutAsksAboutAPendingTransfer() async {
        let coordinator = makeCoordinator()
        await outbox.setPending(true)

        #expect(await coordinator.authDependencies.hasPendingTransfers())
    }
}
