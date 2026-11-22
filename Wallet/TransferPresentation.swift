import Domain
import Foundation
import TransferFeature

/// One opening of the send-money flow: its account and its own router, so every opening
/// starts on the recipient list.
@MainActor
struct TransferPresentation: Identifiable {
    let id = UUID()
    let source: Account
    let router = TransferRouter()
}
