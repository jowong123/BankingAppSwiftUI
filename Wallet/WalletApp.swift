import SwiftUI

@main
struct WalletApp: App {
    @State private var coordinator = AppCoordinator(environment: .live())

    var body: some Scene {
        WindowGroup {
            AppRootView(coordinator: coordinator)
        }
    }
}
