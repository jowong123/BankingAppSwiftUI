import Domain
import Foundation
import Testing

@testable import Persistence

/// The time limit turns a transfer that never finishes into a failure, not a hung run.
@Suite(.timeLimit(.minutes(1))) struct TransferOutboxTests {
    @Test func sendsCreateConfirmAndPollsUntilCompleted() async throws {
        let api = FakeTransferAPI()
        let outbox = try makeOutbox(api: api)
        let transfer = try draft()

        _ = try await outbox.send(transfer)

        #expect(await states(of: transfer.id, in: outbox).last == .completed)
        #expect(await api.calls == [.create, .confirm, .status])
        #expect(await outbox.hasPending() == false)
    }

    /// The row exists before the server hears about it: a crash during the create loses nothing.
    @Test func savesAuthorisedBeforeTheCreate() async throws {
        let api = FakeTransferAPI()
        let gate = Gate()
        await api.hold(.create, at: gate)
        let outbox = try makeOutbox(api: api)
        let transfer = try draft()

        let sent = try await outbox.send(transfer)

        #expect(sent.state == .authorised)
        #expect(await outbox.hasPending())
        await gate.open()
        #expect(await states(of: transfer.id, in: outbox).last == .completed)
    }

    @Test func sendingTheSameDraftTwiceCreatesOneTransfer() async throws {
        let api = FakeTransferAPI()
        let gate = Gate()
        await api.hold(.create, at: gate)
        let outbox = try makeOutbox(api: api)
        let transfer = try draft()

        let first = try await outbox.send(transfer)
        let second = try await outbox.send(transfer)
        await gate.open()

        #expect(first == second)
        #expect(await states(of: transfer.id, in: outbox).last == .completed)
        #expect(await api.count(.create) == 1)
    }

    /// The app was killed with the create in flight. A new outbox on the same store picks
    /// it up on launch and finishes it.
    @Test func resumesAfterTheAppIsKilled() async throws {
        let directory = temporaryDirectory()
        let transfer = try draft()
        let neverAnswers = FakeTransferAPI()
        await neverAnswers.hold(.create, at: Gate())
        let killed = try makeOutbox(api: neverAnswers, directory: directory)
        _ = try await killed.send(transfer)

        let api = FakeTransferAPI()
        let relaunched = try makeOutbox(api: api, directory: directory)
        await relaunched.resumePending()

        #expect(await states(of: transfer.id, in: relaunched).last == .completed)
        #expect(await api.calls == [.create, .confirm, .status])
    }

    /// A timeout is never a failure: wait, back off, ask again.
    @Test func unknownOutcomesAreRetriedWithBackOff() async throws {
        let api = FakeTransferAPI()
        await api.script(.create, .failure(.outcomeUnknown), .failure(.outcomeUnknown))
        let sleeps = Sleeps()
        let outbox = try makeOutbox(api: api, sleeps: sleeps)
        let transfer = try draft()

        _ = try await outbox.send(transfer)

        #expect(await states(of: transfer.id, in: outbox).last == .completed)
        #expect(await api.count(.create) == 3)
        #expect(await sleeps.delays() == [.seconds(2), .seconds(4)])
    }

    @Test func backOffStopsGrowingAtThirtySeconds() async throws {
        let api = FakeTransferAPI()
        await api.script(.status, .success(.processing), .success(.processing), .success(.processing))
        await api.script(.status, .success(.processing), .success(.processing), .success(.processing))
        let sleeps = Sleeps()
        let outbox = try makeOutbox(api: api, sleeps: sleeps)
        let transfer = try draft()

        _ = try await outbox.send(transfer)

        #expect(await states(of: transfer.id, in: outbox).last == .completed)
        let seconds: [Duration] = [2, 4, 8, 16, 30, 30].map {
            .seconds($0)
        }
        #expect(await sleeps.delays() == seconds)
    }

    /// The server already has it (the response was lost): fetch it instead of failing.
    @Test func createThatAlreadyExistsIsFetched() async throws {
        let api = FakeTransferAPI()
        await api.script(.create, .failure(.exists))
        await api.script(.status, .success(.awaitingConfirmation))
        let outbox = try makeOutbox(api: api)
        let transfer = try draft()

        _ = try await outbox.send(transfer)

        #expect(await states(of: transfer.id, in: outbox).last == .completed)
        #expect(await api.calls == [.create, .status, .confirm, .status])
    }

    /// The server doesn't know the transfer yet: the create may still be in flight, so it
    /// is sent again with the same ID.
    @Test func confirmForAnUnknownTransferResendsTheCreate() async throws {
        let api = FakeTransferAPI()
        await api.script(.confirm, .failure(.notFound))
        let outbox = try makeOutbox(api: api)
        let transfer = try draft()

        _ = try await outbox.send(transfer)

        #expect(await states(of: transfer.id, in: outbox).last == .completed)
        #expect(await api.calls == [.create, .confirm, .create, .confirm, .status])
    }

    @Test(arguments: [TransferFailure.quoteExpired, .insufficientFunds])
    func refusedCreateFailsWithTheReason(reason: TransferFailure) async throws {
        let api = FakeTransferAPI()
        await api.script(.create, .failure(.rejected(reason)))
        let outbox = try makeOutbox(api: api)
        let transfer = try draft()

        _ = try await outbox.send(transfer)

        var last: Transfer?
        for await update in await outbox.updates(for: transfer.id) {
            last = update
        }
        #expect(last?.state == .failed)
        #expect(last?.failure == reason)
        #expect(await api.count(.confirm) == 0)
    }

    @Test func declinedAtSettlementFails() async throws {
        let api = FakeTransferAPI()
        await api.script(.status, .success(.failed(.declined)))
        let outbox = try makeOutbox(api: api)
        let transfer = try draft()

        _ = try await outbox.send(transfer)

        var last: Transfer?
        for await update in await outbox.updates(for: transfer.id) {
            last = update
        }
        #expect(last?.state == .failed)
        #expect(last?.failure == .declined)
    }

    /// Signing out mid-transfer: the late answer must not write the transfer back or go on
    /// to confirm it.
    @Test func removeAllStopsAndForgetsEverything() async throws {
        let api = FakeTransferAPI()
        let gate = Gate()
        await api.hold(.create, at: gate)
        let outbox = try makeOutbox(api: api)
        let transfer = try draft()
        _ = try await outbox.send(transfer)

        await outbox.removeAll()
        await gate.open()
        await api.waitUntilReturned(.create)
        for _ in 0..<100 {
            await Task.yield()
        }

        #expect(await outbox.hasPending() == false)
        #expect(await api.calls == [.create])
        var updates = await outbox.updates(for: transfer.id).makeAsyncIterator()
        #expect(await updates.next() == nil)
    }

    /// The dangerous direction: Submitted must be on disk while the confirm (which moves
    /// the money) is on the network, so a crash then resumes with a confirm, not a create.
    @Test func savesSubmittedBeforeTheConfirm() async throws {
        let api = FakeTransferAPI()
        let gate = Gate()
        await api.hold(.confirm, at: gate)
        let outbox = try makeOutbox(api: api)
        let transfer = try draft()
        _ = try await outbox.send(transfer)
        for _ in 0..<1_000 where await api.count(.confirm) == 0 {
            await Task.yield()
        }

        var updates = await outbox.updates(for: transfer.id).makeAsyncIterator()
        #expect(await updates.next()?.state == .submitted)

        await gate.open()
        #expect(await states(of: transfer.id, in: outbox).last == .completed)
    }

    /// Subscribing while the transfer is moving still ends on its final state.
    @Test func listenerThatJoinsMidwaySeesTheEnd() async throws {
        let api = FakeTransferAPI()
        let gate = Gate()
        await api.hold(.status, at: gate)
        let outbox = try makeOutbox(api: api)
        let transfer = try draft()
        _ = try await outbox.send(transfer)

        async let seen = states(of: transfer.id, in: outbox)
        await gate.open()

        #expect(await seen.last == .completed)
    }

    /// The session ended under it: stop, keep the row, and let `removeAll` decide.
    @Test func sessionExpiredStopsWithoutFailing() async throws {
        let api = FakeTransferAPI()
        await api.script(.create, .failure(.sessionExpired))
        let sleeps = Sleeps()
        let outbox = try makeOutbox(api: api, sleeps: sleeps)
        let transfer = try draft()

        _ = try await outbox.send(transfer)
        var updates = await outbox.updates(for: transfer.id).makeAsyncIterator()

        #expect(await updates.next()?.state == .authorised)
        #expect(await outbox.hasPending())
        #expect(await sleeps.delays().isEmpty)
    }

    @Test func storeFolderIsLeftOutOfBackups() async throws {
        let directory = temporaryDirectory()
        let outbox = try makeOutbox(api: FakeTransferAPI(), directory: directory)
        _ = try await outbox.send(try draft())

        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    // MARK: - Session end and storage

    /// Rows deleted inside SQLite can linger in free pages; the files go instead.
    @Test func removeAllDeletesTheStoreFiles() async throws {
        let directory = temporaryDirectory()
        let outbox = try makeOutbox(api: FakeTransferAPI(), directory: directory)
        _ = try await outbox.send(try draft())

        await outbox.removeAll()

        #expect(!FileManager.default.fileExists(atPath: directory.path()))
    }

    /// A Send that lands after the session ended is refused, until a session resumes the outbox.
    @Test func sendAfterTheSessionEndedIsRefused() async throws {
        let outbox = try makeOutbox(api: FakeTransferAPI())
        await outbox.removeAll()

        await #expect(throws: TransferError.sessionExpired) {
            try await outbox.send(try draft())
        }
        await outbox.resumePending()
        _ = try await outbox.send(try draft())
    }

    /// The store can't be opened (here: a file sits where its folder should be). Nothing is
    /// sent, and "is anything pending?" says yes so sign-out still warns.
    @Test func unreadableStoreFailsClosed() async throws {
        let blocked = temporaryDirectory()
        try Data("not a folder".utf8).write(to: blocked)
        let api = FakeTransferAPI()
        let outbox = try makeOutbox(api: api, directory: blocked)

        await #expect(throws: TransferError.storageUnavailable) {
            try await outbox.send(try draft())
        }
        #expect(await outbox.hasPending())
        #expect(await api.calls.isEmpty)
    }

    /// Finished transfers are in the account history; their details leave the device.
    @Test func finishedTransfersAreDeletedOnResume() async throws {
        let outbox = try makeOutbox(api: FakeTransferAPI())
        let transfer = try draft()
        _ = try await outbox.send(transfer)
        #expect(await states(of: transfer.id, in: outbox).last == .completed)

        #expect(await outbox.stored(transfer.id) != nil)

        await outbox.resumePending()

        #expect(await outbox.stored(transfer.id) == nil)
    }
}
