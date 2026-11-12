import AccountsFeature
import AuthFeature
import DesignSystem
import Domain
import Foundation
import Navigation
import Networking
import Observability
import OnboardingFeature
import Persistence
import TransferFeature
import WalletSecurity

/// Composition root: builds every concrete dependency once and passes it down
/// through initialisers. No singletons, no service locator.
///
/// The session store supplies tokens to `WalletAPI`; sign-in and refresh go through
/// `RemoteAuthAPI`, which needs no tokens, so the two don't depend on each other.
struct AppEnvironment: Sendable {
    let linkedModules: [String]
    let session: any SessionManaging
    let accounts: AccountsDependencies
    let transfers: TransferDependencies
    /// Sends and resumes transfers. Wiped whenever the session ends.
    let outbox: any TransferOutboxing
    let autoLock: AutoLockPolicy
    /// `nil` in the UI-test mock, which starts empty every launch anyway.
    let firstLaunch: (any FirstLaunchMarker)?
    /// Debug `-resetSession`: sign out at launch, so a test leaves no session behind.
    let resetSessionOnLaunch: Bool

    var auth: AuthDependencies {
        AuthDependencies(
            session: session,
            hasPendingTransfers: { [outbox] in
                await outbox.hasPending()
            })
    }

    /// The backend comes from `WalletAPIBaseURL` in the build's Info.plist
    /// (`Config/Wallet-Debug.plist`, `Config/Wallet-Release.plist`).
    ///
    /// Debug launch arguments, used by UI tests (SPEC section 8):
    /// - `-mockServer`: in-memory sign-in, storage and accounts; no backend needed.
    /// - `-uiTesting`: no simulated network delay. `-simulateOffline`: accounts fail offline.
    /// - `-autoLockSeconds <n>`: lock after n seconds instead of 5 and 2 minutes.
    /// - `-resetSession`: sign out at launch.
    /// - `-quoteSeconds <n>`: quotes hold n seconds instead of 30. `-transferDelay <n>`: each
    ///   transfer call takes n seconds. `-keepMockSession`: the mock session survives a relaunch.
    static func live(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        info: [String: Any]? = Bundle.main.infoDictionary
    ) -> AppEnvironment {
        #if DEBUG
            if arguments.contains("-mockServer") {
                return mock(arguments: arguments)
            }
            let resetSession = arguments.contains("-resetSession")
        #else
            let resetSession = false
        #endif
        let store = KeychainStore(service: keychainService)
        guard let baseURL = baseURL(from: info) else {
            let session = SessionStore(api: UnconfiguredAuthAPI(), store: store, biometrics: DeviceBiometrics())
            return make(
                services: Services(
                    session: session,
                    accounts: UnconfiguredAccountsRepository(),
                    transfers: UnconfiguredTransfersRepository(),
                    outbox: outbox(named: outboxFolder, api: UnconfiguredTransferAPI())
                ),
                autoLock: autoLockPolicy(arguments),
                firstLaunch: DefaultsFirstLaunchMarker(),
                resetSession: resetSession
            )
        }
        let session = SessionStore(api: RemoteAuthAPI(baseURL: baseURL), store: store, biometrics: DeviceBiometrics())
        // One client for every feature: one AuthInterceptor, so one refresh at a time. Two
        // would refresh in parallel with the same rotating token and sign the user out
        // (ADR-016). The transfer calls take this same `api`.
        let api = WalletAPI(baseURL: baseURL, tokens: session)
        return make(
            services: Services(
                session: session,
                accounts: RemoteAccountsRepository(api: api),
                transfers: RemoteTransfersRepository(api: api),
                outbox: outbox(named: outboxFolder, api: RemoteTransferAPI(api: api))
            ),
            autoLock: autoLockPolicy(arguments),
            firstLaunch: DefaultsFirstLaunchMarker(),
            resetSession: resetSession
        )
    }

    static let keychainService = "jw.Wallet.session"
    static let outboxFolder = "Outbox"

    /// The outbox store in Application Support. It opens on first use, so a launch while the
    /// phone is locked doesn't break it; until it can open, nothing is sent (ADR-009).
    private static func outbox(named folder: String, api: any TransferAPI) -> any TransferOutboxing {
        TransferOutbox(
            directory: URL.applicationSupportDirectory.appending(path: folder, directoryHint: .isDirectory),
            api: api
        )
    }

    static func baseURL(from info: [String: Any]?) -> URL? {
        guard let text = info?["WalletAPIBaseURL"] as? String, let url = URL(string: text), url.host() != nil
        else {
            return nil
        }
        return url
    }

    /// The implementations one environment is built from: real, unconfigured or mock.
    private struct Services {
        let session: SessionStore
        let accounts: any AccountsRepository
        let transfers: any TransfersRepository
        let outbox: any TransferOutboxing
    }

    private static func make(
        services: Services,
        autoLock: AutoLockPolicy,
        firstLaunch: (any FirstLaunchMarker)?,
        resetSession: Bool
    ) -> AppEnvironment {
        AppEnvironment(
            linkedModules: [
                moduleName(of: Money.self),
                moduleName(of: PrimaryButton.self),
                NavigationModule.name,
                moduleName(of: WalletAPI.self),
                moduleName(of: SessionStore.self),
                moduleName(of: TransferOutbox.self),
                ObservabilityModule.name,
                moduleName(of: AuthFlowView.self),
                OnboardingFeatureModule.name,
                moduleName(of: AccountsFlowView.self),
                moduleName(of: TransferFlowView.self),
            ],
            session: services.session,
            accounts: AccountsDependencies(repository: services.accounts),
            transfers: TransferDependencies(repository: services.transfers, outbox: services.outbox),
            outbox: services.outbox,
            autoLock: autoLock,
            firstLaunch: firstLaunch,
            resetSessionOnLaunch: resetSession
        )
    }

    private static func autoLockPolicy(_ arguments: [String]) -> AutoLockPolicy {
        #if DEBUG
            if let index = arguments.firstIndex(of: "-autoLockSeconds"), index + 1 < arguments.count,
                let seconds = Int(arguments[index + 1])
            {
                return AutoLockPolicy(inactivityLimit: .seconds(seconds), backgroundLimit: .seconds(seconds))
            }
        #endif
        return AutoLockPolicy()
    }

    #if DEBUG
        /// Everything in memory except the outbox, which needs a file to survive a kill. It
        /// lives in its own folder and, like the real one, is wiped when there's no session.
        private static func mock(arguments: [String]) -> AppEnvironment {
            let delay = arguments.contains("-uiTesting") ? Duration.zero : .milliseconds(600)
            let bank = MockBank(quoteLifetime: TimeInterval(number(after: "-quoteSeconds", in: arguments) ?? 30))
            let transferDelay = number(after: "-transferDelay", in: arguments).map(Duration.seconds) ?? delay
            // A UI test that relaunches mid-transfer needs the session to survive: the real
            // Keychain under a test-only service. Otherwise nothing outlives the process.
            let store: any SecureStore =
                arguments.contains("-keepMockSession")
                ? KeychainStore(service: "jw.Wallet.uitest") : InMemorySecureStore()
            return make(
                services: Services(
                    session: SessionStore(api: MockAuthAPI(), store: store, biometrics: NoBiometrics()),
                    accounts: MockAccountsRepository(
                        bank: bank,
                        isOffline: arguments.contains("-simulateOffline"),
                        delay: delay
                    ),
                    transfers: MockTransfersRepository(bank: bank, delay: delay),
                    outbox: outbox(named: "Outbox-Mock", api: MockTransferAPI(bank: bank, delay: transferDelay))
                ),
                autoLock: autoLockPolicy(arguments),
                firstLaunch: nil,
                resetSession: arguments.contains("-resetSession")
            )
        }

        private static func number(after flag: String, in arguments: [String]) -> Int? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
                return nil
            }
            return Int(arguments[index + 1])
        }
    #endif

    /// "Domain.Money" -> "Domain". For modules whose Phase 1 placeholder has been replaced.
    private static func moduleName(of type: Any.Type) -> String {
        String(
            String(reflecting: type).prefix {
                $0 != "."
            })
    }
}
