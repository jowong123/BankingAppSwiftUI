import Foundation
import Observation
import SwiftUI

/// Owns the send-money flow's navigation. View models call it; views never navigate.
@Observable @MainActor
public final class TransferRouter {
    public var path = NavigationPath()
    public var sheet: TransferRoute?
    /// Set once the transfer is in the outbox. The flow then shows its status in place of
    /// everything before it, so there's no way back to the review screen.
    public private(set) var sentTransferID: UUID?

    public init() {}

    public func push(_ route: TransferRoute) {
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

    public func present(_ route: TransferRoute) {
        sheet = route
    }

    public func dismiss() {
        sheet = nil
    }

    func showStatus(of id: UUID) {
        sentTransferID = id
        path = NavigationPath()
    }
}
