import Domain
import SwiftUI

/// The only public view of the feature: sign in, create a PIN, or unlock a saved session.
///
/// - Parameter onSessionChange: called with every new session state. `AppCoordinator`
///   switches the app's root on it (to Accounts once `.unlocked`).
public struct AuthFlowView: View {
    @Bindable private var router: AuthRouter
    private let start: AuthStart
    private let dependencies: AuthDependencies
    private let onSessionChange: @MainActor (SessionState) -> Void

    public init(
        start: AuthStart,
        router: AuthRouter,
        dependencies: AuthDependencies,
        onSessionChange: @escaping @MainActor (SessionState) -> Void
    ) {
        self.start = start
        self.router = router
        self.dependencies = dependencies
        self.onSessionChange = onSessionChange
    }

    public var body: some View {
        switch start {
        case .unlock:
            UnlockScreen(dependencies: dependencies, onSessionChange: onSessionChange)
        case .createPIN:
            NavigationStack {
                CreatePINScreen(dependencies: dependencies, onSessionChange: onSessionChange)
            }
        case .signIn(let notice):
            NavigationStack(path: $router.path) {
                SignInScreen(notice: notice, dependencies: dependencies, onSessionChange: onSessionChange)
                    // A new notice means a new screen, so it is always shown.
                    .id(notice)
            }
        }
    }
}

/// Each screen owns its view model for as long as it is on screen.
private struct SignInScreen: View {
    @State private var viewModel: SignInViewModel

    init(
        notice: SignInNotice?,
        dependencies: AuthDependencies,
        onSessionChange: @escaping @MainActor (SessionState) -> Void
    ) {
        _viewModel = State(
            initialValue: SignInViewModel(
                notice: notice,
                dependencies: dependencies,
                onSessionChange: onSessionChange
            )
        )
    }

    var body: some View {
        SignInView(viewModel: viewModel)
    }
}

private struct CreatePINScreen: View {
    @State private var viewModel: CreatePINViewModel

    init(dependencies: AuthDependencies, onSessionChange: @escaping @MainActor (SessionState) -> Void) {
        _viewModel = State(
            initialValue: CreatePINViewModel(dependencies: dependencies, onSessionChange: onSessionChange))
    }

    var body: some View {
        CreatePINView(viewModel: viewModel)
    }
}

private struct UnlockScreen: View {
    @State private var viewModel: UnlockViewModel

    init(dependencies: AuthDependencies, onSessionChange: @escaping @MainActor (SessionState) -> Void) {
        _viewModel = State(initialValue: UnlockViewModel(dependencies: dependencies, onSessionChange: onSessionChange))
    }

    var body: some View {
        UnlockView(viewModel: viewModel)
    }
}
