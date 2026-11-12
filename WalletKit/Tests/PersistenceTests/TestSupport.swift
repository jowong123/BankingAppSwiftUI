import Domain
import Foundation
import Testing

@testable import Persistence

/// Holds callers until opened.
actor Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
        if isOpen {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters = []
    }
}

/// A scripted server. Each call takes the next scripted answer for its kind, then falls
/// back to the default: a transfer that is created, confirmed and settles on the first poll.
actor FakeTransferAPI: TransferAPI {
    enum Call: Hashable {
        case create
        case confirm
        case status
    }

    private(set) var calls: [Call] = []
    /// Calls that have finished, answered or thrown.
    private(set) var returned: [Call] = []
    private var scripts: [Call: [Result<RemoteTransferStatus, TransferAPIError>]] = [:]
    private var gates: [Call: Gate] = [:]

    func script(_ call: Call, _ answers: Result<RemoteTransferStatus, TransferAPIError>...) {
        scripts[call, default: []].append(contentsOf: answers)
    }

    /// Holds every call of this kind at `gate` until it opens.
    func hold(_ call: Call, at gate: Gate) {
        gates[call] = gate
    }

    /// Waits, a scheduler turn at a time, until `count` calls of this kind have finished.
    func waitUntilReturned(_ call: Call, count: Int = 1) async {
        for _ in 0..<1_000
        where returned.filter({
            $0 == call
        }).count < count {
            await Task.yield()
        }
    }

    func count(_ call: Call) -> Int {
        calls.filter {
            $0 == call
        }.count
    }

    func create(_ draft: TransferDraft) async throws(TransferAPIError) -> RemoteTransferStatus {
        try await answer(.create, default: .awaitingConfirmation)
    }

    func confirm(id: UUID) async throws(TransferAPIError) -> RemoteTransferStatus {
        try await answer(.confirm, default: .processing)
    }

    func status(id: UUID) async throws(TransferAPIError) -> RemoteTransferStatus {
        try await answer(.status, default: .completed)
    }

    private func answer(_ call: Call, default fallback: RemoteTransferStatus)
        async throws(TransferAPIError) -> RemoteTransferStatus
    {
        calls.append(call)
        await gates[call]?.wait()
        defer {
            returned.append(call)
        }
        guard var queue = scripts[call], !queue.isEmpty else {
            return fallback
        }
        let next = queue.removeFirst()
        scripts[call] = queue
        return try next.get()
    }
}

/// Records each back-off delay without waiting.
final class Sleeps: Sendable {
    private let recorded = Recorded()

    var sleep: @Sendable (Duration) async throws -> Void {
        { [recorded] delay in
            await recorded.append(delay)
            try Task.checkCancellation()
        }
    }

    func delays() async -> [Duration] {
        await recorded.values
    }

    private actor Recorded {
        var values: [Duration] = []

        func append(_ delay: Duration) {
            values.append(delay)
        }
    }
}

func draft(id: UUID = UUID()) throws -> TransferDraft {
    let rate = try FXRate(source: .sgd, target: .usd, rate: Decimal(string: "0.7341") ?? 0)
    let quote = try FXQuote(
        id: "q_1",
        sourceAmount: Money(amountMinor: 10_000, currency: .sgd),
        targetAmount: Money(amountMinor: 7_230, currency: .usd),
        rate: rate,
        fee: Money(amountMinor: 150, currency: .sgd),
        expiresAt: Date(timeIntervalSince1970: 1_800_000_030)
    )
    let recipient = Recipient(id: "rcp_alice_usd", name: "Alice Tan", currency: .usd, accountLast4: "4821")
    return TransferDraft(id: id, quote: quote, recipient: recipient, sourceAccountID: "acc_sgd")
}

func makeOutbox(
    api: FakeTransferAPI,
    sleeps: Sleeps = Sleeps(),
    directory: URL? = nil
) throws -> TransferOutbox {
    TransferOutbox(
        directory: directory,
        api: api,
        now: {
            Date(timeIntervalSince1970: 1_800_000_000)
        },
        sleep: sleeps.sleep
    )
}

/// The states a transfer goes through until it finishes.
func states(of id: UUID, in outbox: TransferOutbox) async -> [TransferState] {
    var seen: [TransferState] = []
    for await transfer in await outbox.updates(for: id) {
        seen.append(transfer.state)
    }
    return seen
}

func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "outbox-tests-\(UUID().uuidString)")
}
