import Domain
import Foundation
import Observation

/// Follows one transfer in the outbox until it finishes. Leaving the screen doesn't stop
/// the transfer: the outbox keeps sending it.
@Observable @MainActor
final class StatusViewModel {
    struct State: Equatable {
        var transfer: Transfer?

        var title: String {
            guard let transfer else {
                return TransferStrings.sendingTitle
            }
            switch transfer.state {
            case .processing:
                return TransferStrings.processingTitle
            case .completed:
                return TransferStrings.completedTitle
            case .failed:
                return TransferStrings.failedTitle(transfer.failure ?? .rejected)
            default:
                return TransferStrings.sendingTitle
            }
        }

        var message: String {
            guard let transfer else {
                return TransferStrings.sendingMessage
            }
            let name = transfer.draft.recipient.name
            switch transfer.state {
            case .processing:
                return TransferStrings.processingMessage(name)
            case .completed:
                return TransferStrings.completedMessage(name)
            case .failed:
                return TransferStrings.failedMessage(transfer.failure ?? .rejected)
            default:
                return TransferStrings.sendingMessage
            }
        }

        var isFinished: Bool {
            transfer?.state.isTerminal ?? false
        }
    }

    private(set) var state = State()
    let transferID: UUID
    private let outbox: any TransferOutboxing
    private let onFinish: @MainActor () -> Void

    init(transferID: UUID, dependencies: TransferDependencies, onFinish: @escaping @MainActor () -> Void) {
        self.transferID = transferID
        self.outbox = dependencies.outbox
        self.onFinish = onFinish
    }

    func observe() async {
        for await transfer in await outbox.updates(for: transferID) {
            state.transfer = transfer
        }
    }

    func done() {
        onFinish()
    }
}
