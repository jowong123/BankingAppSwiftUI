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
            TransferDraft(
                id: UUID(), quote: quote, recipient: MockBank.recipients[0], sourceAccountID: "acc_sgd",
                confirmation: approval))

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
            TransferDraft(
                id: UUID(), quote: quote, recipient: MockBank.recipients[0], sourceAccountID: "acc_sgd",
                confirmation: approval))

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
            id: UUID(), quote: quote, recipient: MockBank.recipients[0], sourceAccountID: "acc_sgd",
            confirmation: approval)

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

/// A stand-in approval; these tests are about storage and the mock bank, not signatures.
private let approval = SignedConfirmation(payload: Data("p".utf8), signature: Data("s".utf8), assertion: nil)

/// TLS pins from Info.plist (ADR-006): only 32-byte SHA-256 values count.
@Suite struct PinConfigurationTests {
    @Test func primaryAndBackupPinsAreKept() {
        let pins = [Data(repeating: 7, count: 32), Data(repeating: 8, count: 32)]

        let values = pins.map {
            $0.base64EncodedString()
        }

        #expect(AppEnvironment.pins(from: ["WalletAPIPins": values]) == Set(pins))
    }

    /// A typo in one pin, or no backup, would turn the next key rotation into an outage: no
    /// pins at all, so it fails now and is noticed.
    @Test(arguments: [
        ["not base64!", Data(repeating: 7, count: 32).base64EncodedString()],
        [Data(repeating: 1, count: 20).base64EncodedString(), Data(repeating: 7, count: 32).base64EncodedString()],
        [Data(repeating: 7, count: 32).base64EncodedString()],
    ])
    func malformedOrSinglePinGivesNone(values: [String]) {
        #expect(AppEnvironment.pins(from: ["WalletAPIPins": values]).isEmpty)
    }

    @Test func missingPinsAreEmptySoHTTPSFailsClosed() {
        #expect(AppEnvironment.pins(from: [:]).isEmpty)
        #expect(AppEnvironment.pins(from: nil).isEmpty)
    }
}
