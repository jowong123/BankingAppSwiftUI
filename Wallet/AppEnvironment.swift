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
/// Phase 1 only proves that every WalletKit module links into the app.
struct AppEnvironment: Sendable {
    let linkedModules: [String]

    static func live() -> AppEnvironment {
        AppEnvironment(
            linkedModules: [
                DomainModule.name,
                DesignSystemModule.name,
                NavigationModule.name,
                NetworkingModule.name,
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
}
