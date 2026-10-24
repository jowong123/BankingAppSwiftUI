import Observation
import SwiftUI

/// Composes the feature flows and handles their output closures.
/// Phase 1 placeholder: shows a root screen until the first feature lands.
@Observable @MainActor
final class AppCoordinator {
    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var linkedModuleCount: Int { environment.linkedModules.count }
}

struct AppRootView: View {
    let coordinator: AppCoordinator

    var body: some View {
        VStack(spacing: 8) {
            Text("Wallet")
                .font(.largeTitle.bold())
            Text("\(coordinator.linkedModuleCount) modules linked")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("app.root")
    }
}

#Preview {
    AppRootView(coordinator: AppCoordinator(environment: .live()))
}
