import Observation
import SwiftUI

/// Owns the Accounts flow's navigation. View models call it; views never navigate themselves.
@Observable @MainActor
public final class AccountsRouter {
    public var path = NavigationPath()
    public var sheet: AccountsRoute?

    public init() {}

    public func push(_ route: AccountsRoute) {
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

    public func present(_ route: AccountsRoute) {
        sheet = route
    }

    public func dismiss() {
        sheet = nil
    }
}
