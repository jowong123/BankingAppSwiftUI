import Domain
import Foundation

/// Everything the send-money flow needs, as Domain protocols plus the clock the quote
/// countdown runs on. `AppEnvironment` passes the real ones; tests pass fakes and a clock
/// they move.
public struct TransferDependencies: Sendable {
    public let repository: any TransfersRepository
    public let outbox: any TransferOutboxing
    public let now: @Sendable () -> Date
    public let sleep: @Sendable (Duration) async throws -> Void

    public init(
        repository: any TransfersRepository,
        outbox: any TransferOutboxing,
        now: @escaping @Sendable () -> Date = {
            Date()
        },
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.repository = repository
        self.outbox = outbox
        self.now = now
        self.sleep = sleep
    }
}
