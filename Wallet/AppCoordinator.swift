import AccountsFeature
import AuthFeature
import Domain
import Foundation
import Observation
import SwiftUI
import TransferFeature

/// Composes the feature flows from the session state, and locks the app on its own after
/// inactivity or time in the background (SPEC section 4).
///
/// Time is measured with `ContinuousClock`, which keeps counting while the phone sleeps and
/// ignores the device's date settings, so turning the clock back can't stop the lock.
@Observable @MainActor
final class AppCoordinator {
    enum Root: Equatable {
        /// Reading the Keychain at launch.
        case launching
        case signIn(SignInNotice?)
        /// Signed in, choosing a PIN. Times out to signed out, never to "locked".
        case createPIN
        case unlock
        case accounts
    }

    private(set) var root = Root.launching
    /// True from going to the background until the lock decision on return is made, so the
    /// privacy cover never lifts on balances that are about to be locked.
    private(set) var needsLockCheck = false
    let accountsRouter = AccountsRouter()
    private(set) var authRouter = AuthRouter()
    /// The send-money flow over Accounts, while it's open.
    private(set) var transfer: TransferPresentation?
    /// Bumped when a transfer flow closes, so Accounts shows the new balance.
    private(set) var accountsReload = 0
    private let environment: AppEnvironment
    private let now: () -> ContinuousClock.Instant
    private var lastActivity: ContinuousClock.Instant
    private var backgroundedAt: ContinuousClock.Instant?
    private var expiryTask: Task<Void, Never>?

    init(
        environment: AppEnvironment,
        now: @escaping () -> ContinuousClock.Instant = {
            ContinuousClock.now
        }
    ) {
        self.environment = environment
        self.now = now
        self.lastActivity = now()
    }

    var accountsDependencies: AccountsDependencies {
        environment.accounts
    }

    var authDependencies: AuthDependencies {
        environment.auth
    }

    var transferDependencies: TransferDependencies {
        environment.transfers
    }

    /// Balances, or a live session waiting for its PIN: both time out.
    var isTimed: Bool {
        root == .accounts || root == .createPIN
    }

    /// How often to check for inactivity while the app is open: often enough that a short
    /// test limit works, rarely enough to cost nothing.
    var inactivityCheckInterval: Duration {
        min(.seconds(15), max(.milliseconds(500), environment.autoLock.inactivityLimit / 3))
    }

    /// A fresh install (or `-resetSession`) wipes any session iOS kept in the Keychain from
    /// before, then reads what is stored.
    func start() async {
        if environment.resetSessionOnLaunch || environment.firstLaunch?.isFirstLaunch() == true {
            _ = await environment.session.signOut()
            environment.firstLaunch?.markLaunched()
        }
        apply(await environment.session.restore())
    }

    /// Follows the session for changes nobody here asked for: a refused token refresh in a
    /// background call signs out (SPEC section 6). Runs after `start()`, never before: until
    /// `restore()` has read the Keychain the store reports `.signedOut`.
    func observeSession() async {
        for await state in await environment.session.stateUpdates() {
            guard state == .signedOut else {
                continue
            }
            switch root {
            case .accounts:
                apply(.signedOut, notice: .sessionExpired)
            case .createPIN, .unlock:
                apply(.signedOut)
            case .launching, .signIn:
                break
            }
        }
    }

    func sendMoney(from account: Account) {
        transfer = TransferPresentation(source: account)
    }

    func transferFinished() {
        transfer = nil
        accountsReload += 1
    }

    /// From AuthFeature after sign-in, PIN creation, unlock or sign-out.
    func sessionChanged(_ state: SessionState) {
        apply(state)
    }

    /// From AccountsFeature when the server won't renew the session. The store has already
    /// wiped it; signing out again makes sure, then shows why.
    func sessionExpired() {
        expiryTask?.cancel()
        expiryTask = Task {
            _ = await environment.session.signOut()
            apply(.signedOut, notice: .sessionExpired)
        }
    }

    func userInteracted() {
        lastActivity = now()
    }

    func enteredBackground() {
        backgroundedAt = now()
        needsLockCheck = true
    }

    /// Counts both the time away and the idle time before leaving: 4 minutes idle plus
    /// 1.5 minutes away is 5.5 minutes without use.
    func becameActive() async {
        defer {
            backgroundedAt = nil
            needsLockCheck = false
        }
        let current = now()
        let away =
            backgroundedAt.map {
                current - $0
            } ?? .zero
        let policy = environment.autoLock
        if isTimed, policy.shouldLockOnReturn(away: away) || policy.shouldLock(idle: current - lastActivity) {
            await timeOut()
        }
        // A send that stopped while the phone was locked (the store is unreadable then) picks
        // up again.
        if root == .accounts || root == .unlock {
            await environment.outbox.resumePending()
        }
    }

    func checkInactivity() async {
        if isTimed, environment.autoLock.shouldLock(idle: now() - lastActivity) {
            await timeOut()
        }
    }

    /// Balances lock; an unfinished PIN setup signs out, so whoever picks up the phone
    /// can't choose the PIN for someone else's session.
    private func timeOut() async {
        if root == .createPIN {
            apply(await environment.session.signOut())
        } else {
            apply(await environment.session.lock())
        }
    }

    /// Runs on every root change (`AppRootView`). Signed in: carry on with pending transfers.
    /// Sign-in screen: there is no session to send them with, so they are deleted, like the
    /// tokens. Tied to the root rather than to session events, so no sign-out path (Unlock,
    /// expiry, five wrong PINs, a launch with no session) can skip it.
    func rootChanged() async {
        switch root {
        case .signIn:
            await environment.outbox.removeAll()
        case .accounts, .unlock:
            await environment.outbox.resumePending()
        case .launching, .createPIN:
            break
        }
    }

    private func apply(_ state: SessionState, notice: SignInNotice? = nil) {
        if state != .unlocked {
            transfer = nil
        }
        switch state {
        case .signedOut:
            if root != .signIn(notice) {
                authRouter = AuthRouter()
            }
            accountsRouter.popToRoot()
            root = .signIn(notice)
        case .needsPIN:
            lastActivity = now()
            root = .createPIN
        case .locked:
            root = .unlock
        case .unlocked:
            lastActivity = now()
            root = .accounts
        }
    }
}

struct AppRootView: View {
    let coordinator: AppCoordinator
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .overlay {
                if scenePhase != .active || coordinator.needsLockCheck {
                    PrivacyCover()
                }
            }
            .background {
                ActivityMonitor {
                    coordinator.userInteracted()
                }
            }
            .task {
                await coordinator.start()
                await coordinator.observeSession()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    coordinator.enteredBackground()
                }
            }
            .task(id: scenePhase) {
                if scenePhase == .active {
                    await coordinator.becameActive()
                }
            }
            .task(id: coordinator.root) {
                await coordinator.rootChanged()
                // Only while something times out; cancelled when the root changes.
                while coordinator.isTimed, !Task.isCancelled {
                    try? await Task.sleep(for: coordinator.inactivityCheckInterval)
                    await coordinator.checkInactivity()
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch coordinator.root {
        case .launching:
            ProgressView()
        case .signIn(let notice):
            AuthFlowView(
                start: .signIn(notice),
                router: coordinator.authRouter,
                dependencies: coordinator.authDependencies,
                onSessionChange: { state in
                    coordinator.sessionChanged(state)
                }
            )
        case .createPIN:
            AuthFlowView(
                start: .createPIN,
                router: coordinator.authRouter,
                dependencies: coordinator.authDependencies,
                onSessionChange: { state in
                    coordinator.sessionChanged(state)
                }
            )
        case .unlock:
            AuthFlowView(
                start: .unlock,
                router: coordinator.authRouter,
                dependencies: coordinator.authDependencies,
                onSessionChange: { state in
                    coordinator.sessionChanged(state)
                }
            )
        case .accounts:
            AccountsFlowView(
                router: coordinator.accountsRouter,
                dependencies: coordinator.accountsDependencies,
                reloadTrigger: coordinator.accountsReload,
                onSessionExpired: {
                    coordinator.sessionExpired()
                },
                onSendMoney: { account in
                    coordinator.sendMoney(from: account)
                }
            )
            .fullScreenCover(
                item: Binding(
                    get: {
                        coordinator.transfer
                    },
                    set: { _ in
                    }
                )
            ) { presentation in
                TransferFlowView(
                    router: presentation.router,
                    dependencies: coordinator.transferDependencies,
                    source: presentation.source,
                    onFinish: {
                        coordinator.transferFinished()
                    },
                    onSessionExpired: {
                        coordinator.sessionExpired()
                    }
                )
            }
        }
    }
}

#Preview {
    AppRootView(coordinator: AppCoordinator(environment: .live(arguments: ["-mockServer", "-uiTesting"])))
}
