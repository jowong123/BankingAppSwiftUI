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
    /// (`Config/Wallet-Debug.plist`, `Config/Wallet-Release.plist`), its TLS pins from
    /// `WalletAPIPins` (ADR-006).
    ///
    /// The signing key is the Secure Enclave's on a phone. The simulator has none, so it gets
    /// `SoftwareKey`: a key it generates itself, behind the same Face ID rules (ADR-023).
    ///
    /// Debug launch arguments, used by UI tests (SPEC section 8):
    /// - `-mockServer`: in-memory sign-in, storage and accounts; no backend needed.
    /// - `-uiTesting`: no simulated network delay. `-simulateOffline`: accounts fail offline.
    /// - `-autoLockSeconds <n>`: lock after n seconds instead of 5 and 2 minutes.
    /// - `-resetSession`: sign out at launch.
    /// - `-quoteSeconds <n>`: quotes hold n seconds instead of 30. `-transferDelay <n>`: each
    ///   transfer call takes n seconds. `-keepMockSession`: the mock session survives a relaunch.
    /// - `-signing keyInvalidated|biometryNotSetUp`: the mock device can't approve transfers.
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
        let device = Device(store: store)
        guard let baseURL = baseURL(from: info) else {
            return make(
                services: Services(
                    session: device.session(api: UnconfiguredAuthAPI()),
                    accounts: UnconfiguredAccountsRepository(),
                    transfers: UnconfiguredTransfersRepository(),
                    outbox: outbox(named: outboxFolder, api: UnconfiguredTransferAPI()),
                    signer: device.signer
                ),
                autoLock: autoLockPolicy(arguments),
                firstLaunch: DefaultsFirstLaunchMarker(),
                resetSession: resetSession
            )
        }
        let pins = pins(from: info)
        let session = device.session(api: RemoteAuthAPI(baseURL: baseURL, pins: pins))
        // One client for every feature: one AuthInterceptor, so one refresh at a time. Two
        // would refresh in parallel with the same rotating token and sign the user out
        // (ADR-016). The transfer calls take this same `api`.
        let api = WalletAPI(baseURL: baseURL, tokens: session, pins: pins)
        return make(
            services: Services(
                session: session,
                accounts: RemoteAccountsRepository(api: api),
                transfers: RemoteTransfersRepository(api: api),
                outbox: outbox(named: outboxFolder, api: RemoteTransferAPI(api: api)),
                signer: device.signer
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

    /// Base64 SHA-256 SPKI hashes: the current key and at least one backup (ADR-006). A
    /// malformed entry, or fewer than two, gives no pins at all, so an https host fails closed
    /// at once rather than at the next key rotation.
    static func pins(from info: [String: Any]?) -> Set<Data> {
        let values = info?["WalletAPIPins"] as? [String] ?? []
        let pins = values.compactMap {
            Data(base64Encoded: $0)
        }
        .filter {
            $0.count == 32
        }
        guard pins.count == values.count, Set(pins).count >= 2 else {
            return []
        }
        return Set(pins)
    }

    /// The device's signing key and App Attest, shared by the session (which makes the key
    /// at sign-in) and the signer (which uses it on Send).
    private struct Device {
        let store: any SecureStore
        let key: any DeviceKey
        let attestor: any AppAttesting

        init(store: any SecureStore) {
            self.store = store
            #if targetEnvironment(simulator)
                key = SoftwareKey(store: store, biometrics: DeviceBiometrics())
            #else
                key = SecureEnclaveKey(store: store, biometrics: DeviceBiometrics())
            #endif
            attestor = DeviceAppAttest()
        }

        var signer: any TransferSigning {
            TransferSigner(key: key, attestor: attestor, store: store)
        }

        func session(api: any AuthAPI) -> SessionStore {
            SessionStore(api: api, store: store, biometrics: DeviceBiometrics(), deviceKey: key, attestor: attestor)
        }
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
        let signer: any TransferSigning
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
            transfers: TransferDependencies(
                repository: services.transfers, outbox: services.outbox, signer: services.signer),
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
                    // No biometrics, so the session binds without a key; `MockSigner` signs.
                    session: SessionStore(
                        api: MockAuthAPI(),
                        store: store,
                        biometrics: NoBiometrics(),
                        deviceKey: SoftwareKey(store: store, biometrics: NoBiometrics()),
                        attestor: MockSigner.NoAppAttest()
                    ),
                    accounts: MockAccountsRepository(
                        bank: bank,
                        isOffline: arguments.contains("-simulateOffline"),
                        delay: delay
                    ),
                    transfers: MockTransfersRepository(bank: bank, delay: delay),
                    outbox: outbox(named: "Outbox-Mock", api: MockTransferAPI(bank: bank, delay: transferDelay)),
                    signer: MockSigner(availability: signingAvailability(arguments))
                ),
                autoLock: autoLockPolicy(arguments),
                firstLaunch: nil,
                resetSession: arguments.contains("-resetSession")
            )
        }

        private static func signingAvailability(_ arguments: [String]) -> SigningAvailability {
            guard let index = arguments.firstIndex(of: "-signing"), index + 1 < arguments.count else {
                return .ready
            }
            switch arguments[index + 1] {
            case "keyInvalidated": return .keyInvalidated
            case "biometryNotSetUp": return .biometryNotSetUp
            default: return .ready
            }
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
