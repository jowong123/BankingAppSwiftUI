import Domain
import Foundation
import Persistence
import Testing

@testable import Wallet

/// The outbox store with the real file system.
@Suite struct OutboxStorageTests {
    #if targetEnvironment(simulator)
        static let onDevice = false
    #else
        static let onDevice = true
    #endif

    /// Nothing about a pending transfer can be read while the phone is locked (ADR-009).
    /// The simulator has no data protection and reports no protection class, so the check
    /// runs on a device: `xcodebuild test -destination 'platform=iOS,name=<device>'`.
    @Test(.enabled(if: onDevice, "the simulator has no file protection"))
    func storeIsCompletelyProtected() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "outbox-\(UUID().uuidString)")
        let outbox = TransferOutbox(directory: directory, api: UnconfiguredTransferAPI())
        let bank = MockBank()
        let quote = try await bank.quote(
            sourceAmount: Money(amountMinor: 10_000, currency: .sgd), targetCurrency: .usd)
        _ = try await outbox.send(
            TransferDraft(id: UUID(), quote: quote, recipient: MockBank.recipients[0], sourceAccountID: "acc_sgd"))

        let folder = try FileManager.default.attributesOfItem(atPath: directory.path())
        let store = try FileManager.default.attributesOfItem(atPath: directory.appending(path: "outbox.store").path())
        await outbox.removeAll()

        #expect(folder[.protectionKey] as? FileProtectionType == .complete)
        #expect(store[.protectionKey] as? FileProtectionType == .complete)
    }

    @Test func storeIsLeftOutOfBackups() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "outbox-\(UUID().uuidString)")
        let outbox = try TransferOutbox(directory: directory, api: UnconfiguredTransferAPI())
        let bank = MockBank()
        let quote = try await bank.quote(
            sourceAmount: Money(amountMinor: 10_000, currency: .sgd), targetCurrency: .usd)
        _ = try await outbox.send(
            TransferDraft(id: UUID(), quote: quote, recipient: MockBank.recipients[0], sourceAccountID: "acc_sgd"))

        let backup = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        await outbox.removeAll()

        #expect(backup.isExcludedFromBackup == true)
    }
}

/// The `-mockServer` bank behaves like the backend, so UI tests see the same effects.
@Suite struct MockBankTests {
    /// Same numbers as the backend for 100.00 SGD to USD: fee 1.00, receive 73.81.
    @Test func quoteMatchesTheBackendMaths() async throws {
        let quote = try await MockBank().quote(
            sourceAmount: Money(amountMinor: 10_000, currency: .sgd), targetCurrency: .usd)

        #expect(quote.fee == Money(amountMinor: 100, currency: .sgd))
        #expect(quote.targetAmount == Money(amountMinor: 7_381, currency: .usd))
    }

    @Test func confirmDebitsOnceAndAddsTheHistoryRow() async throws {
        let bank = MockBank(settleDelay: 0)
        let quote = try await bank.quote(sourceAmount: Money(amountMinor: 10_000, currency: .sgd), targetCurrency: .usd)
        let draft = TransferDraft(
            id: UUID(), quote: quote, recipient: MockBank.recipients[0], sourceAccountID: "acc_sgd")

        #expect(await bank.create(draft) == .awaitingConfirmation)
        #expect(await bank.confirm(draft.id) == .processing)
        #expect(await bank.confirm(draft.id) == .processing)
        #expect(await bank.status(draft.id) == .completed)

        let balance = await bank.accounts().first?.balance
        #expect(balance == Money(amountMinor: 1_240_000, currency: .sgd))
        let newest = await bank.transactions("acc_sgd").first
        #expect(newest?.description == "To Alice Tan")
    }

    @Test func amountBelowTheFeeIsRefused() async {
        await #expect(throws: TransferError.amountNotAllowed) {
            try await MockBank().quote(sourceAmount: Money(amountMinor: 100, currency: .sgd), targetCurrency: .usd)
        }
    }
}
