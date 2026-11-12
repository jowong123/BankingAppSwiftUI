import Domain
import Foundation
import Testing
import os

@testable import TransferFeature

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

/// A clock the test moves: `sleep` advances `now` instead of waiting.
final class TestClock: Sendable {
    private let current = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_800_000_000))

    var now: @Sendable () -> Date {
        { [current] in
            current.withLock {
                $0
            }
        }
    }

    var sleep: @Sendable (Duration) async throws -> Void {
        { [current] duration in
            try Task.checkCancellation()
            let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
            current.withLock {
                $0 = $0.addingTimeInterval(seconds)
            }
            await Task.yield()
        }
    }

    func advance(_ seconds: TimeInterval) {
        current.withLock {
            $0 = $0.addingTimeInterval(seconds)
        }
    }
}

actor FakeTransfersRepository: TransfersRepository {
    var recipientsResult: Result<[Recipient], TransferError> = .success(Sample.recipients)
    private var quoteResults: [Result<FXQuote, TransferError>] = []
    private(set) var quoteRequests: [Money] = []
    /// Quotes it makes when nothing is scripted expire 30 s after this clock's time.
    private let clock: TestClock

    init(clock: TestClock) {
        self.clock = clock
    }

    func set(recipients: Result<[Recipient], TransferError>) {
        recipientsResult = recipients
    }

    func script(quotes: Result<FXQuote, TransferError>...) {
        quoteResults.append(contentsOf: quotes)
    }

    func recipients() async throws(TransferError) -> [Recipient] {
        try recipientsResult.get()
    }

    func quote(sourceAmount: Money, targetCurrency: Currency) async throws(TransferError) -> FXQuote {
        quoteRequests.append(sourceAmount)
        guard !quoteResults.isEmpty else {
            return Sample.quote(id: "q_\(quoteRequests.count)", expiresAt: clock.now().addingTimeInterval(30))
        }
        return try quoteResults.removeFirst().get()
    }
}

actor FakeOutbox: TransferOutboxing {
    private(set) var sent: [TransferDraft] = []
    var sendError: TransferError?
    private var gate: Gate?
    private var streams: [UUID: AsyncStream<Transfer>] = [:]

    func failSends(with error: TransferError) {
        sendError = error
    }

    func holdSends(at gate: Gate) {
        self.gate = gate
    }

    /// What `updates(for:)` replays for `id`.
    func setUpdates(_ transfers: [Transfer], for id: UUID) {
        streams[id] = AsyncStream { continuation in
            for transfer in transfers {
                continuation.yield(transfer)
            }
            continuation.finish()
        }
    }

    func send(_ draft: TransferDraft) async throws(TransferError) -> Transfer {
        sent.append(draft)
        await gate?.wait()
        if let sendError {
            throw sendError
        }
        return Transfer(draft: draft, state: .authorised, createdAt: .now, updatedAt: .now)
    }

    func updates(for id: UUID) async -> AsyncStream<Transfer> {
        streams[id]
            ?? AsyncStream {
                $0.finish()
            }
    }

    func resumePending() async {}

    func hasPending() async -> Bool {
        false
    }

    func removeAll() async {}
}

enum Sample {
    static let account = Account(id: "acc_sgd", balance: Money(amountMinor: 1_250_000, currency: .sgd), updatedAt: .now)
    static let alice = Recipient(id: "rcp_alice_usd", name: "Alice Tan", currency: .usd, accountLast4: "4821")
    static let sgdPayee = Recipient(id: "rcp_sgd", name: "Same Currency", currency: .sgd, accountLast4: "1234")
    static let recipients = [alice, sgdPayee]

    static func quote(id: String = "q_1", expiresAt: Date) -> FXQuote {
        guard let rate = try? FXRate(source: .sgd, target: .usd, rate: Decimal(string: "0.7341") ?? 1),
            let quote = try? FXQuote(
                id: id,
                sourceAmount: Money(amountMinor: 10_000, currency: .sgd),
                targetAmount: Money(amountMinor: 7_230, currency: .usd),
                rate: rate,
                fee: Money(amountMinor: 150, currency: .sgd),
                expiresAt: expiresAt
            )
        else {
            preconditionFailure("sample quote")
        }
        return quote
    }

    static func transfer(_ state: TransferState, failure: TransferFailure? = nil, id: UUID = UUID()) -> Transfer {
        let draft = TransferDraft(
            id: id,
            quote: quote(expiresAt: .now),
            recipient: alice,
            sourceAccountID: "acc_sgd"
        )
        return Transfer(draft: draft, state: state, failure: failure, createdAt: .now, updatedAt: .now)
    }
}

/// Counts `onSessionExpired` and `onFinish` calls.
@MainActor final class Outputs {
    private(set) var sessionExpired = 0
    private(set) var finished = 0

    func expire() {
        sessionExpired += 1
    }

    func finish() {
        finished += 1
    }
}

@MainActor
func dependencies(
    repository: FakeTransfersRepository,
    outbox: FakeOutbox = FakeOutbox(),
    clock: TestClock
) -> TransferDependencies {
    TransferDependencies(repository: repository, outbox: outbox, now: clock.now, sleep: clock.sleep)
}
