import Observation
import SwiftUI

/// Owns the sign-in flow's navigation. View models call it; views never navigate themselves.
@Observable @MainActor
public final class AuthRouter {
    public var path = NavigationPath()
    public var sheet: AuthRoute?

    public init() {}

    public func push(_ route: AuthRoute) {
        path.append(route)
    }

    public func pop() {
        if !path.isEmpty {
            path.removeLast()
        }
    }

    public func popToRoot() {
        path = NavigationPath()
    }

    public func present(_ route: AuthRoute) {
        sheet = route
    }

    public func dismiss() {
        sheet = nil
    }
}
