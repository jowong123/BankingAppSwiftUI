import Foundation

/// The transfer outbox as features and the app see it. `TransferOutbox` in Persistence
/// implements it: every state is saved on the device before the network call it leads
/// to, so a crash or a lost connection never loses or doubles a transfer (ADR-009, ADR-022).
public protocol TransferOutboxing: Sendable {
    /// Saves the transfer as `.authorised` and starts sending it. Sending the same draft
    /// again returns the transfer already saved and sends nothing new.
    func send(_ draft: TransferDraft) async throws(TransferError) -> Transfer

    /// The transfer now, then every change until it ends or the caller stops listening.
    func updates(for id: UUID) async -> AsyncStream<Transfer>

    /// Restarts every transfer that hasn't finished. Called at launch and on return to the app.
    func resumePending() async

    func hasPending() async -> Bool

    /// Stops and deletes everything: the session has ended.
    func removeAll() async
}
