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
/// Accounts runs on sandbox data (Debug) until Phase 5 adds the session store; then this
/// builds `WalletAPI` and passes `RemoteAccountsRepository(api:)` instead.
struct AppEnvironment: Sendable {
    let linkedModules: [String]
    let accounts: AccountsDependencies

    /// Debug launch arguments: `-simulateOffline` makes every load fail as if there were no
    /// connection; `-uiTesting` removes the simulated network delay. Release ignores them.
    static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppEnvironment {
        #if DEBUG
            let repository: any AccountsRepository = SandboxAccountsRepository(
                isOffline: arguments.contains("-simulateOffline"),
                delay: arguments.contains("-uiTesting") ? .zero : .milliseconds(600)
            )
        #else
            let repository: any AccountsRepository = UnconnectedAccountsRepository()
        #endif
        return AppEnvironment(
            linkedModules: [
                moduleName(of: Money.self),
                moduleName(of: PrimaryButton.self),
                NavigationModule.name,
                moduleName(of: WalletAPI.self),
                WalletSecurityModule.name,
                PersistenceModule.name,
                ObservabilityModule.name,
                AuthFeatureModule.name,
                OnboardingFeatureModule.name,
                moduleName(of: AccountsFlowView.self),
                TransferFeatureModule.name,
            ],
            accounts: AccountsDependencies(repository: repository)
        )
    }

    /// "Domain.Money" -> "Domain". For modules whose Phase 1 placeholder has been replaced.
    private static func moduleName(of type: Any.Type) -> String {
        String(
            String(reflecting: type).prefix {
                $0 != "."
            })
    }
}
