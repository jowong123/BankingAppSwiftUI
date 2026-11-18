import Domain
import Foundation

extension SessionStore {
    /// Only the newest state is buffered: a listener that falls behind needs where the
    /// session is now, not every step on the way.
    public func stateUpdates() async -> AsyncStream<SessionState> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: SessionState.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let id = UUID()
        listeners[id] = continuation
        continuation.yield(state)
        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.removeListener(id)
            }
        }
        return stream
    }

    private func removeListener(_ id: UUID) {
        listeners[id] = nil
    }
}
