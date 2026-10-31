import AccountsFeature
import AuthFeature
import DesignSystem
import Domain
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
/// So far this only proves that every WalletKit module links into the app. `WalletAPI`
/// is built here once the session store exists (Phase 5) to supply its tokens.
struct AppEnvironment: Sendable {
    let linkedModules: [String]

    static func live() -> AppEnvironment {
        AppEnvironment(
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
                AccountsFeatureModule.name,
                TransferFeatureModule.name,
            ]
        )
    }

    /// "Domain.Money" -> "Domain". For modules whose Phase 1 placeholder has been replaced.
    private static func moduleName(of type: Any.Type) -> String {
        String(String(reflecting: type).prefix { $0 != "." })
    }
}
