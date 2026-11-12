import Domain
import Foundation

/// Sends transfers so that a crash, a lost connection or a double tap never loses or
/// doubles one (SPEC section 5, ADR-009, ADR-022).
///
/// - Every state is saved before the network call it leads to: Authorised before the
///   create, Submitted before the confirm.
/// - What to do next comes from `TransferRecovery`: create, confirm or poll. Every call is
///   safe to repeat, so after an unknown outcome the outbox waits and asks again, backing
///   off from 2 s to 30 s. A timeout never fails a transfer.
/// - One task per transfer. `generation` is bumped by `removeAll()`, so a call that returns
///   after the session ended can't write the transfer back.
/// - The store opens on first use, not at init: the app can launch while the phone is locked
///   (`.complete` keeps the file closed then), and a failed open is tried again next time.
/// - Ending the session deletes the store's files, not just its rows, so nothing is left in
///   free pages. A delete that fails is retried before the store is used again.
public actor TransferOutbox: TransferOutboxing {
    private let directory: URL?
    private var openStore: OutboxStore?
    private var wipePending = false
    /// Off from `removeAll()` until `resumePending()`: with no session, nothing new is sent.
    private var isAccepting = true
    private let api: any TransferAPI
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var listeners: [UUID: [UUID: AsyncStream<Transfer>.Continuation]] = [:]
    /// The newest state told to listeners, per transfer. A new listener gets this rather than
    /// an older row read from the store while a save was landing.
    private var published: [UUID: Transfer] = [:]
    private var generation = 0

    static let firstRetryDelay = Duration.seconds(2)
    static let maxRetryDelay = Duration.seconds(30)

    /// - Parameter directory: where the store lives; `nil` keeps it in memory.
    public init(directory: URL?, api: any TransferAPI) {
        self.init(
            directory: directory,
            api: api,
            now: {
                Date()
            },
            sleep: {
                try await Task.sleep(for: $0)
            }
        )
    }

    init(
        directory: URL?,
        api: any TransferAPI,
        now: @escaping @Sendable () -> Date,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.directory = directory
        self.api = api
        self.now = now
        self.sleep = sleep
    }

    // MARK: - TransferOutboxing

    public func send(_ draft: TransferDraft) async throws(TransferError) -> Transfer {
        guard isAccepting else {
            throw .sessionExpired
        }
        let started = generation
        let created = now()
        let transfer: Transfer
        do {
            transfer = try await store().insertIfAbsent(
                Transfer(draft: draft, state: .authorised, createdAt: created, updatedAt: created)
            )
        } catch {
            throw .storageUnavailable
        }
        // The session ended while saving: the row went with the old store's files.
        guard started == generation else {
            throw .sessionExpired
        }
        start(transfer.id)
        return transfer
    }

    /// Listens before reading the store: the read suspends the actor, and a change saved in
    /// the meantime must reach this stream. Of the stored row and the newest published state,
    /// the one further along is sent, so the screen never steps back.
    public func updates(for id: UUID) async -> AsyncStream<Transfer> {
        let (stream, continuation) = AsyncStream.makeStream(of: Transfer.self, bufferingPolicy: .bufferingNewest(1))
        let token = UUID()
        listeners[id, default: [:]][token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.stopListening(id, token: token)
            }
        }
        let stored = try? await store().transfer(id)
        // Already finished meanwhile: it ended, or the session did.
        guard listeners[id]?[token] != nil else {
            return stream
        }
        guard let current = Self.furthest(stored, published[id]) else {
            listeners[id]?[token] = nil
            continuation.finish()
            return stream
        }
        continuation.yield(current)
        if current.state.isTerminal {
            listeners[id]?[token] = nil
            continuation.finish()
        }
        return stream
    }

    /// Also opens the outbox for new sends again, and deletes finished transfers: their
    /// outcome is in the account history, so their details needn't stay on the device.
    public func resumePending() async {
        isAccepting = true
        guard let store = try? store() else {
            return
        }
        try? await store.removeFinished()
        guard let pending = try? await store.unfinished() else {
            return
        }
        for transfer in pending {
            start(transfer.id)
        }
    }

    /// Fails closed: if the store can't be read, there may be something pending, so the
    /// sign-out warning still shows.
    public func hasPending() async -> Bool {
        do {
            return try await !store().unfinished().isEmpty
        } catch {
            return true
        }
    }

    public func removeAll() async {
        generation += 1
        for task in tasks.values {
            task.cancel()
        }
        tasks = [:]
        for continuations in listeners.values {
            for continuation in continuations.values {
                continuation.finish()
            }
        }
        listeners = [:]
        published = [:]
        isAccepting = false
        openStore = nil
        do {
            try deleteFiles()
        } catch {
            wipePending = true
        }
    }

    // MARK: - Sending

    /// Starts the transfer's task unless one is already running.
    private func start(_ id: UUID) {
        guard tasks[id] == nil else {
            return
        }
        let started = generation
        tasks[id] = Task {
            await self.run(id, generation: started)
        }
    }

    private func run(_ id: UUID, generation started: Int) async {
        var delay = Self.firstRetryDelay
        while !Task.isCancelled, started == generation {
            let transfer: Transfer
            do {
                // No row: the session ended and the outbox was emptied.
                guard let stored = try await store().transfer(id) else {
                    break
                }
                transfer = stored
            } catch {
                // Unreadable for now, e.g. the phone locked (`.complete`): try again later.
                guard await wait(&delay) else {
                    break
                }
                continue
            }
            let step = TransferRecovery.step(for: transfer.state)
            guard step != .done else {
                break
            }
            let outcome = await perform(step, for: transfer)
            guard started == generation, await handle(outcome, for: transfer, delay: &delay) else {
                break
            }
        }
        if started == generation {
            tasks[id] = nil
        }
    }

    /// Records what the server said. `true` to carry on with the next step.
    private func handle(
        _ outcome: Result<RemoteTransferStatus, TransferAPIError>,
        for transfer: Transfer,
        delay: inout Duration
    ) async -> Bool {
        switch outcome {
        case .success(let remote):
            let events = TransferRecovery.events(from: transfer.state, to: remote)
            // Nothing new (still processing, or a status this app doesn't know): ask later.
            guard !events.isEmpty else {
                return await wait(&delay)
            }
            delay = Self.firstRetryDelay
            return await save(transfer, after: events, failure: remote.failure, delay: &delay)
        case .failure(.rejected(let reason)):
            guard let event = TransferRecovery.refusalEvent(at: transfer.state) else {
                return await wait(&delay)
            }
            return await save(transfer, after: [event], failure: reason, delay: &delay)
        case .failure(.sessionExpired), .failure(.cancelled):
            // The session ended, and `removeAll()` follows.
            return false
        case .failure(.outcomeUnknown), .failure(.notFound), .failure(.exists):
            return await wait(&delay)
        }
    }

    /// Applies `events`, saves, and tells listeners. An invalid event stops the task (`false`).
    /// A failed write (e.g. the phone locked) waits and carries on: the loop reads the old
    /// state again and repeats the server call, which is safe to repeat.
    private func save(
        _ transfer: Transfer,
        after events: [TransferEvent],
        failure: TransferFailure?,
        delay: inout Duration
    ) async -> Bool {
        var updated = transfer
        do {
            for event in events {
                updated.state = try TransferStateMachine.next(updated.state, event)
            }
        } catch {
            return false
        }
        updated.failure = updated.state == .failed ? failure : nil
        updated.updatedAt = now()
        do {
            try await store().update(updated)
        } catch {
            return await wait(&delay)
        }
        publish(updated)
        return true
    }

}

// MARK: - Storage and helpers

extension TransferOutbox {
    /// One server call for `step`, with the carry-over rules: a create the server already
    /// has is fetched, and a confirm for a transfer the server doesn't know resends the
    /// create (it may still have been in flight), both safe because they key on the ID.
    private func perform(
        _ step: TransferRecovery.Step,
        for transfer: Transfer
    ) async -> Result<RemoteTransferStatus, TransferAPIError> {
        do throws(TransferAPIError) {
            switch step {
            case .create:
                do throws(TransferAPIError) {
                    return .success(try await api.create(transfer.draft))
                } catch .exists {
                    return .success(try await api.status(id: transfer.id))
                }
            case .confirm:
                do throws(TransferAPIError) {
                    return .success(try await api.confirm(id: transfer.id))
                } catch .notFound {
                    _ = try await api.create(transfer.draft)
                    return .success(try await api.confirm(id: transfer.id))
                }
            case .poll:
                return .success(try await api.status(id: transfer.id))
            case .done:
                return .failure(.cancelled)
            }
        } catch {
            return .failure(error)
        }
    }

    /// Sleeps for `delay`, then doubles it up to the maximum. `false` if cancelled.
    private func wait(_ delay: inout Duration) async -> Bool {
        do {
            try await sleep(delay)
        } catch {
            return false
        }
        delay = min(delay * 2, Self.maxRetryDelay)
        return !Task.isCancelled
    }

    private func publish(_ transfer: Transfer) {
        published[transfer.id] = transfer
        guard let continuations = listeners[transfer.id] else {
            return
        }
        for continuation in continuations.values {
            continuation.yield(transfer)
            if transfer.state.isTerminal {
                continuation.finish()
            }
        }
        if transfer.state.isTerminal {
            listeners[transfer.id] = nil
        }
    }

    private func stopListening(_ id: UUID, token: UUID) {
        listeners[id]?[token] = nil
    }
    private func store() throws -> OutboxStore {
        if wipePending {
            try deleteFiles()
            wipePending = false
        }
        if let openStore {
            return openStore
        }
        let opened = try OutboxStore.make(directory: directory)
        openStore = opened
        return opened
    }

    /// The saved row, for tests.
    func stored(_ id: UUID) async -> Transfer? {
        try? await store().transfer(id)
    }

    /// An in-memory store goes with its last reference.
    private func deleteFiles() throws {
        guard let directory, FileManager.default.fileExists(atPath: directory.path()) else {
            return
        }
        try FileManager.default.removeItem(at: directory)
    }

    /// The one further along in the lifecycle; on a tie, `published` (it is the newer write).
    private static func furthest(_ stored: Transfer?, _ published: Transfer?) -> Transfer? {
        guard let stored, let published else {
            return published ?? stored
        }
        return progress(stored.state) > progress(published.state) ? stored : published
    }

    private static func progress(_ state: TransferState) -> Int {
        switch state {
        case .draft, .quoted, .expired: 0
        case .authorised: 1
        case .submitted: 2
        case .processing: 3
        case .completed, .failed: 4
        }
    }
}
