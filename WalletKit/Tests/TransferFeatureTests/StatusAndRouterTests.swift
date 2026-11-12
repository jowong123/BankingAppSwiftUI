import Domain
import Foundation
import Testing

@testable import TransferFeature

@MainActor
@Suite struct StatusViewModelTests {
    @Test func followsTheTransferUntilItFinishes() async {
        let outbox = FakeOutbox()
        let id = UUID()
        await outbox.setUpdates(
            [
                Sample.transfer(.submitted, id: id), Sample.transfer(.processing, id: id),
                Sample.transfer(.completed, id: id),
            ],
            for: id
        )
        let clock = TestClock()
        let viewModel = StatusViewModel(
            transferID: id,
            dependencies: dependencies(repository: FakeTransfersRepository(clock: clock), outbox: outbox, clock: clock),
            onFinish: {}
        )

        await viewModel.observe()

        #expect(viewModel.state.transfer?.state == .completed)
        #expect(viewModel.state.title == TransferStrings.completedTitle)
        #expect(viewModel.state.message.contains("Alice Tan"))
        #expect(viewModel.state.isFinished)
    }

    @Test(arguments: [TransferState.authorised, .submitted])
    func beforeTheServerAcceptsItSaysItsSafeToLeave(state: TransferState) {
        let shown = StatusViewModel.State(transfer: Sample.transfer(state))

        #expect(shown.title == TransferStrings.sendingTitle)
        #expect(shown.message == TransferStrings.sendingMessage)
        #expect(!shown.isFinished)
    }

    /// Each failure says what happened and whether money moved.
    @Test(arguments: TransferFailure.allCases)
    func everyFailureHasItsOwnText(failure: TransferFailure) {
        let shown = StatusViewModel.State(transfer: Sample.transfer(.failed, failure: failure))

        #expect(shown.title == TransferStrings.failedTitle(failure))
        #expect(!shown.title.hasPrefix("transfer."))
        #expect(!shown.message.hasPrefix("transfer."))
    }

    @Test func doneFinishesTheFlow() {
        let outputs = Outputs()
        let clock = TestClock()
        let viewModel = StatusViewModel(
            transferID: UUID(),
            dependencies: dependencies(repository: FakeTransfersRepository(clock: clock), clock: clock),
            onFinish: outputs.finish
        )

        viewModel.done()

        #expect(outputs.finished == 1)
    }
}

@MainActor
@Suite struct TransferRouterTests {
    @Test func showingTheStatusClearsTheStack() {
        let router = TransferRouter()
        router.push(.amount(Sample.alice))
        router.push(.review(Sample.alice, Sample.quote(expiresAt: .now)))
        let id = UUID()

        router.showStatus(of: id)

        #expect(router.path.isEmpty)
        #expect(router.sentTransferID == id)
    }

    @Test func pushPopAndPresent() {
        let router = TransferRouter()
        router.push(.amount(Sample.alice))
        router.pop()
        router.pop()
        #expect(router.path.isEmpty)

        router.present(.amount(Sample.alice))
        #expect(router.sheet == .amount(Sample.alice))
        router.dismiss()
        #expect(router.sheet == nil)
    }
}

@Suite struct TransferMessagesTests {
    @Test(arguments: [
        (TransferError.offline, true),
        (.unavailable, true),
        (.sessionExpired, false),
        (.amountNotAllowed, false),
        (.invalidData, true),
        (.storageUnavailable, true),
    ])
    func everyErrorBecomesAMessage(error: TransferError, canRetry: Bool) throws {
        let shown = try #require(TransferMessages.userFacing(error))

        #expect(!shown.title.hasPrefix("transfer."))
        #expect(!shown.message.hasPrefix("transfer."))
        #expect(shown.canRetry == canRetry)
        #expect(TransferMessages.userFacing(.cancelled) == nil)
    }
}

@Suite struct TransferStringsTests {
    /// Every key the code asks for exists, and the file has no unused keys.
    @Test func everyKeyTheCodeUsesIsInTheStringsFile() throws {
        let source = try String(
            contentsOf: URL(filePath: #filePath)
                .deletingLastPathComponent()
                .appending(path: "../../Sources/TransferFeature/TransferStrings.swift")
                .standardized,
            encoding: .utf8
        )
        var usedKeys = Set(
            source.matches(of: /text\("([^"]+)"\)/).map {
                String($0.output.1)
            })
        // Built from the failure: transfer.status.failed.<kind>.title / .message.
        usedKeys.remove("transfer.status.failed.\\(failureKey(failure)).title")
        usedKeys.remove("transfer.status.failed.\\(failureKey(failure)).message")
        for kind in ["quoteExpired", "insufficientFunds", "declined", "rejected"] {
            usedKeys.insert("transfer.status.failed.\(kind).title")
            usedKeys.insert("transfer.status.failed.\(kind).message")
        }
        let url = try #require(Bundle.module.url(forResource: "Localizable", withExtension: "strings"))
        let table = try #require(NSDictionary(contentsOf: url) as? [String: String])

        for key in usedKeys {
            #expect(table[key] != nil, "\(key) is missing from Localizable.strings")
        }
        #expect(Set(table.keys) == usedKeys, "Localizable.strings has keys the code never uses")
    }
}
