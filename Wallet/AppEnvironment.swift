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
    let autoLock: AutoLockPolicy
    /// `nil` in the UI-test mock, which starts empty every launch anyway.
    let firstLaunch: (any FirstLaunchMarker)?
    /// Debug `-resetSession`: sign out at launch, so a test leaves no session behind.
    let resetSessionOnLaunch: Bool

    var auth: AuthDependencies {
        AuthDependencies(session: session)
    }

    /// The backend comes from `WalletAPIBaseURL` in the build's Info.plist
    /// (`Config/Wallet-Debug.plist`, `Config/Wallet-Release.plist`).
    ///
    /// Debug launch arguments, used by UI tests (SPEC section 8):
    /// - `-mockServer`: in-memory sign-in, storage and accounts; no backend needed.
    /// - `-uiTesting`: no simulated network delay. `-simulateOffline`: accounts fail offline.
    /// - `-autoLockSeconds <n>`: lock after n seconds instead of 5 and 2 minutes.
    /// - `-resetSession`: sign out at launch.
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
                session: session,
                accounts: UnconfiguredAccountsRepository(),
                autoLock: autoLockPolicy(arguments),
                firstLaunch: DefaultsFirstLaunchMarker(),
                resetSession: resetSession
            )
        }
        let session = SessionStore(api: RemoteAuthAPI(baseURL: baseURL), store: store, biometrics: DeviceBiometrics())
        // One client for every feature: one AuthInterceptor, so one refresh at a time. Two
        // would refresh in parallel with the same rotating token and sign the user out
        // (ADR-016). Phase 6's transfer repository takes this same `api`.
        let api = WalletAPI(baseURL: baseURL, tokens: session)
        return make(
            session: session,
            accounts: RemoteAccountsRepository(api: api),
            autoLock: autoLockPolicy(arguments),
            firstLaunch: DefaultsFirstLaunchMarker(),
            resetSession: resetSession
        )
    }

    static let keychainService = "jw.Wallet.session"

    static func baseURL(from info: [String: Any]?) -> URL? {
        guard let text = info?["WalletAPIBaseURL"] as? String, let url = URL(string: text), url.host() != nil
        else {
            return nil
        }
        return url
    }

    private static func make(
        session: SessionStore,
        accounts: any AccountsRepository,
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
                PersistenceModule.name,
                ObservabilityModule.name,
                moduleName(of: AuthFlowView.self),
                OnboardingFeatureModule.name,
                moduleName(of: AccountsFlowView.self),
                TransferFeatureModule.name,
            ],
            session: session,
            accounts: AccountsDependencies(repository: accounts),
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
        private static func mock(arguments: [String]) -> AppEnvironment {
            make(
                session: SessionStore(api: MockAuthAPI(), store: InMemorySecureStore(), biometrics: NoBiometrics()),
                accounts: MockAccountsRepository(
                    isOffline: arguments.contains("-simulateOffline"),
                    delay: arguments.contains("-uiTesting") ? .zero : .milliseconds(600)
                ),
                autoLock: autoLockPolicy(arguments),
                firstLaunch: nil,
                resetSession: false
            )
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
