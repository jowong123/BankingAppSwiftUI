import AccountsFeature
import Observation
import SwiftUI

/// Composes the feature flows and handles their output closures. Accounts is the only
/// flow so far; auth (Phase 5) and transfers (Phase 6) are added here.
@Observable @MainActor
final class AppCoordinator {
    let accountsRouter = AccountsRouter()
    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var accountsDependencies: AccountsDependencies {
        environment.accounts
    }

    /// Phase 5 routes this to sign-in. Until then there is no session to end, and the
    /// Accounts screen already shows "Session expired".
    func sessionExpired() {}
}

struct AppRootView: View {
    let coordinator: AppCoordinator

    var body: some View {
        AccountsFlowView(
            router: coordinator.accountsRouter,
            dependencies: coordinator.accountsDependencies,
            onSessionExpired: {
                coordinator.sessionExpired()
            }
        )
    }
}

#Preview {
    AppRootView(coordinator: AppCoordinator(environment: .live()))
}
