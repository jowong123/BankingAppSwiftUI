import Foundation

/// A transfer the user has sent, as the outbox keeps it (SPEC section 5).
public struct Transfer: Hashable, Sendable, Identifiable {
    public let draft: TransferDraft
    public var state: TransferState
    /// Why it failed, when `state == .failed`.
    public var failure: TransferFailure?
    public let createdAt: Date
    public var updatedAt: Date

    public var id: UUID {
        draft.id
    }

    public init(
        draft: TransferDraft,
        state: TransferState,
        failure: TransferFailure? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.draft = draft
        self.state = state
        self.failure = failure
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
