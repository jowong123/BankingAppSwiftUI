import Domain
import Foundation
import Testing

@testable import TransferFeature

@MainActor
@Suite struct RecipientsViewModelTests {
    let clock = TestClock()

    @Test func listsOnlyRecipientsInAnotherCurrency() async {
        let router = TransferRouter()
        let viewModel = RecipientsViewModel(
            source: Sample.account,
            dependencies: dependencies(repository: FakeTransfersRepository(clock: clock), clock: clock),
            router: router,
            onSessionExpired: {}
        )

        await viewModel.onAppear()

        #expect(viewModel.state.recipients == [Sample.alice])
        viewModel.select(Sample.alice)
        #expect(router.path.count == 1)
    }

    @Test func offlineShowsRetryAndRetryLoads() async {
        let repository = FakeTransfersRepository(clock: clock)
        await repository.set(recipients: .failure(.offline))
        let viewModel = RecipientsViewModel(
            source: Sample.account,
            dependencies: dependencies(repository: repository, clock: clock),
            router: TransferRouter(),
            onSessionExpired: {}
        )

        await viewModel.onAppear()
        #expect(viewModel.state.error?.canRetry == true)

        await repository.set(recipients: .success([Sample.alice]))
        await viewModel.retry()
        #expect(viewModel.state.error == nil)
        #expect(viewModel.state.recipients == [Sample.alice])
    }

    @Test func expiredSessionIsReported() async {
        let repository = FakeTransfersRepository(clock: clock)
        await repository.set(recipients: .failure(.sessionExpired))
        let outputs = Outputs()
        let viewModel = RecipientsViewModel(
            source: Sample.account,
            dependencies: dependencies(repository: repository, clock: clock),
            router: TransferRouter(),
            onSessionExpired: outputs.expire
        )

        await viewModel.onAppear()

        #expect(outputs.sessionExpired == 1)
    }
}

@MainActor
@Suite struct AmountViewModelTests {
    let clock = TestClock()

    func makeViewModel(_ repository: FakeTransfersRepository, router: TransferRouter = TransferRouter())
        -> AmountViewModel
    {
        AmountViewModel(
            source: Sample.account,
            recipient: Sample.alice,
            dependencies: dependencies(repository: repository, clock: clock),
            router: router,
            onSessionExpired: {}
        )
    }

    @Test(arguments: [
        (Int64?.none, false),
        (0, false),
        (10_000, true),
        (1_250_000, true),
        (1_250_001, false),
    ])
    func continueNeedsAnAmountWithinTheBalance(minor: Int64?, allowed: Bool) {
        let viewModel = makeViewModel(FakeTransfersRepository(clock: clock))

        viewModel.setAmount(
            minor.map {
                Money(amountMinor: $0, currency: .sgd)
            })

        #expect(viewModel.state.canContinue == allowed)
    }

    @Test func continueGetsAQuoteAndOpensTheReview() async {
        let repository = FakeTransfersRepository(clock: clock)
        let router = TransferRouter()
        let viewModel = makeViewModel(repository, router: router)
        viewModel.setAmount(Money(amountMinor: 10_000, currency: .sgd))

        await viewModel.continueTapped()

        #expect(await repository.quoteRequests == [Money(amountMinor: 10_000, currency: .sgd)])
        #expect(router.path.count == 1)
    }

    @Test func amountTheServerRefusesSaysSoAndStays() async {
        let repository = FakeTransfersRepository(clock: clock)
        await repository.script(quotes: .failure(.amountNotAllowed))
        let router = TransferRouter()
        let viewModel = makeViewModel(repository, router: router)
        viewModel.setAmount(Money(amountMinor: 100, currency: .sgd))

        await viewModel.continueTapped()

        #expect(viewModel.state.error?.title == TransferStrings.amountNotAllowedTitle)
        #expect(router.path.isEmpty)
        viewModel.setAmount(Money(amountMinor: 10_000, currency: .sgd))
        #expect(viewModel.state.error == nil)
    }
}
