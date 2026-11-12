import Domain
import Foundation
import Testing

@testable import TransferFeature

@MainActor
@Suite(.timeLimit(.minutes(1))) struct ReviewViewModelTests {
    let clock = TestClock()

    func makeViewModel(
        repository: FakeTransfersRepository,
        outbox: FakeOutbox = FakeOutbox(),
        router: TransferRouter = TransferRouter(),
        expiresIn seconds: TimeInterval = 30
    ) -> ReviewViewModel {
        ReviewViewModel(
            source: Sample.account,
            recipient: Sample.alice,
            quote: Sample.quote(expiresAt: clock.now().addingTimeInterval(seconds)),
            dependencies: dependencies(repository: repository, outbox: outbox, clock: clock),
            router: router,
            onSessionExpired: {}
        )
    }

    @Test func showsTheSecondsLeftOnTheQuote() {
        let viewModel = makeViewModel(repository: FakeTransfersRepository(clock: clock), expiresIn: 29.2)

        #expect(viewModel.state.secondsLeft == 30)
        #expect(viewModel.state.canSend)
    }

    /// At 0 s a new quote arrives with a visible notice, and Send waits for the user to OK it.
    @Test func expiryRequotesVisiblyAndSendWaitsForOK() async {
        let repository = FakeTransfersRepository(clock: clock)
        let viewModel = makeViewModel(repository: repository, expiresIn: 3)

        await viewModel.runCountdown()

        #expect(await repository.quoteRequests.count == 1)
        #expect(viewModel.state.quote.id == "q_1")
        #expect(viewModel.state.rateUpdated)
        #expect(viewModel.state.secondsLeft == 30)
        #expect(!viewModel.state.canSend)
        viewModel.acknowledgeNewRate()
        #expect(viewModel.state.canSend)
    }

    @Test func failedRequoteOffersRetry() async {
        let repository = FakeTransfersRepository(clock: clock)
        await repository.script(quotes: .failure(.offline))
        let viewModel = makeViewModel(repository: repository, expiresIn: 1)

        await viewModel.runCountdown()
        #expect(viewModel.state.error?.canRetry == true)
        #expect(!viewModel.state.canSend)

        await viewModel.retry()
        #expect(viewModel.state.error == nil)
        #expect(viewModel.state.rateUpdated)
    }

    @Test func sendPutsTheTransferInTheOutboxAndShowsItsStatus() async throws {
        let outbox = FakeOutbox()
        let router = TransferRouter()
        let viewModel = makeViewModel(repository: FakeTransfersRepository(clock: clock), outbox: outbox, router: router)

        await viewModel.send()

        let sent = try #require(await outbox.sent.first)
        #expect(sent.id == viewModel.transferID)
        #expect(sent.sourceAccountID == "acc_sgd")
        #expect(router.sentTransferID == viewModel.transferID)
    }

    /// Two taps while the first send is still saving: one transfer.
    @Test func doubleTapSendsOnce() async {
        let outbox = FakeOutbox()
        let gate = Gate()
        await outbox.holdSends(at: gate)
        let viewModel = makeViewModel(repository: FakeTransfersRepository(clock: clock), outbox: outbox)

        async let first: Void = viewModel.send()
        async let second: Void = viewModel.send()
        await Task.yield()
        await gate.open()
        _ = await (first, second)

        #expect(await outbox.sent.count == 1)
    }

    /// The countdown ticks once a second, so a tap can land just after expiry: re-quote
    /// instead of sending a quote the server will refuse.
    @Test func sendAfterExpiryRequotesInstead() async {
        let repository = FakeTransfersRepository(clock: clock)
        let outbox = FakeOutbox()
        let viewModel = makeViewModel(repository: repository, outbox: outbox, expiresIn: 5)
        clock.advance(5)

        await viewModel.send()

        #expect(await outbox.sent.isEmpty)
        #expect(viewModel.state.rateUpdated)
    }

    /// The quote runs out while Send is saving: the screen keeps the rate being sent.
    @Test func noRequoteWhileSending() async {
        let repository = FakeTransfersRepository(clock: clock)
        let outbox = FakeOutbox()
        let gate = Gate()
        await outbox.holdSends(at: gate)
        let viewModel = makeViewModel(repository: repository, outbox: outbox, expiresIn: 1)

        async let sending: Void = viewModel.send()
        await Task.yield()
        clock.advance(2)
        await viewModel.runCountdown()
        await gate.open()
        _ = await sending

        #expect(await repository.quoteRequests.isEmpty)
        #expect(!viewModel.state.rateUpdated)
    }

    @Test func failedSaveSaysNothingWasSentAndAllowsAnotherTry() async {
        let outbox = FakeOutbox()
        await outbox.failSends(with: .storageUnavailable)
        let router = TransferRouter()
        let viewModel = makeViewModel(repository: FakeTransfersRepository(clock: clock), outbox: outbox, router: router)

        await viewModel.send()

        #expect(viewModel.state.error?.title == TransferStrings.storageTitle)
        #expect(viewModel.state.canSend)
        #expect(router.sentTransferID == nil)
    }
}
