import Domain
import Foundation
import Testing

@testable import TransferFeature

/// Send asks for Face ID and signs what the screen shows, before the outbox sees anything
/// (SPEC section 6, ADR-023).
@MainActor
@Suite struct ReviewSigningTests {
    let clock = TestClock()

    func makeViewModel(
        repository: FakeTransfersRepository,
        outbox: FakeOutbox = FakeOutbox(),
        signer: FakeSigner = FakeSigner(),
        router: TransferRouter = TransferRouter()
    ) -> ReviewViewModel {
        ReviewViewModel(
            source: Sample.account,
            recipient: Sample.alice,
            quote: Sample.quote(expiresAt: clock.now().addingTimeInterval(30)),
            dependencies: dependencies(repository: repository, outbox: outbox, signer: signer, clock: clock),
            router: router,
            onSessionExpired: {}
        )
    }

    @Test func sendSignsExactlyWhatTheScreenShowsWithTheServersNonce() async throws {
        let repository = FakeTransfersRepository(clock: clock)
        let outbox = FakeOutbox()
        let signer = FakeSigner()
        let viewModel = makeViewModel(repository: repository, outbox: outbox, signer: signer)

        await viewModel.send()

        let payload = try #require(await signer.signed.first)
        #expect(payload.transferID == viewModel.transferID)
        #expect(payload.amountMinor == 10_000)
        #expect(payload.currency == .sgd)
        #expect(payload.recipientID == "rcp_alice_usd")
        #expect(payload.quoteID == "q_1")
        #expect(payload.nonce == "nonce-1")
        #expect(await repository.challengeRequests == [viewModel.transferID])
        #expect(await signer.reasons.first?.contains("Alice Tan") == true)
        #expect(await outbox.sent.first?.confirmation == Sample.confirmation)
    }

    /// Cancelling Face ID sends nothing and shows nothing; Send works again.
    @Test func cancelledFaceIDSendsNothing() async {
        let outbox = FakeOutbox()
        let signer = FakeSigner()
        await signer.fail(with: .cancelled)
        let viewModel = makeViewModel(repository: FakeTransfersRepository(clock: clock), outbox: outbox, signer: signer)

        await viewModel.send()

        #expect(await outbox.sent.isEmpty)
        #expect(viewModel.state.error == nil)
        #expect(viewModel.state.canSend)
    }

    @Test func faceIDThatFailsSaysSoAndSendsNothing() async {
        let outbox = FakeOutbox()
        let signer = FakeSigner()
        await signer.fail(with: .failed)
        let viewModel = makeViewModel(repository: FakeTransfersRepository(clock: clock), outbox: outbox, signer: signer)

        await viewModel.send()

        #expect(await outbox.sent.isEmpty)
        #expect(viewModel.state.error == TransferMessages.signingFailed)
        #expect(viewModel.state.canSend)
    }

    @Test(arguments: [SigningError.keyInvalidated, .biometryNotSetUp])
    func deviceThatCantSignExplainsWhy(error: SigningError) async {
        let outbox = FakeOutbox()
        let signer = FakeSigner()
        await signer.fail(with: error)
        let router = TransferRouter()
        let viewModel = makeViewModel(
            repository: FakeTransfersRepository(clock: clock), outbox: outbox, signer: signer, router: router)

        await viewModel.send()

        #expect(await outbox.sent.isEmpty)
        #expect(router.signingIssue == (error == .keyInvalidated ? .keyInvalidated : .biometryNotSetUp))
    }

    /// The user takes longer at the Face ID prompt than the rate lasts: the approval is
    /// dropped and the new rate shown, rather than sending one the server will refuse.
    @Test func quoteThatExpiresDuringThePromptIsRequotedNotSent() async {
        let repository = FakeTransfersRepository(clock: clock)
        let outbox = FakeOutbox()
        let signer = FakeSigner()
        await signer.whilePromptIsUp { [clock] in
            clock.advance(31)
        }
        let viewModel = makeViewModel(repository: repository, outbox: outbox, signer: signer)

        await viewModel.send()

        #expect(await outbox.sent.isEmpty)
        #expect(viewModel.state.rateUpdated)
        #expect(await repository.quoteRequests.count == 1)
    }

    /// A second tap while the first is at the Face ID prompt asks for nothing more.
    @Test func doubleTapAsksForOneChallengeAndOnePrompt() async {
        let repository = FakeTransfersRepository(clock: clock)
        let signer = FakeSigner()
        let gate = Gate()
        await signer.holdPrompt(at: gate)
        let viewModel = makeViewModel(repository: repository, signer: signer)

        async let first: Void = viewModel.send()
        async let second: Void = viewModel.send()
        await Task.yield()
        await gate.open()
        _ = await (first, second)

        #expect(await repository.challengeRequests.count == 1)
        #expect(await signer.reasons.count == 1)
    }

    @Test func expiredSessionAtTheChallengeSignsOut() async {
        let repository = FakeTransfersRepository(clock: clock)
        await repository.set(challenge: .failure(.sessionExpired))
        let outputs = Outputs()
        let viewModel = ReviewViewModel(
            source: Sample.account,
            recipient: Sample.alice,
            quote: Sample.quote(expiresAt: clock.now().addingTimeInterval(30)),
            dependencies: dependencies(repository: repository, clock: clock),
            router: TransferRouter(),
            onSessionExpired: outputs.expire
        )

        await viewModel.send()

        #expect(outputs.sessionExpired == 1)
    }

    /// No challenge, no prompt: Face ID is never asked for something that can't be sent.
    @Test func noChallengeMeansNoPrompt() async {
        let repository = FakeTransfersRepository(clock: clock)
        await repository.set(challenge: .failure(.offline))
        let signer = FakeSigner()
        let viewModel = makeViewModel(repository: repository, signer: signer)

        await viewModel.send()

        #expect(await signer.signed.isEmpty)
        #expect(viewModel.state.error?.canRetry == true)
        #expect(viewModel.state.canSend)
    }
}

@MainActor
@Suite struct SigningIssueTests {
    let clock = TestClock()

    @Test(arguments: [SigningAvailability.keyInvalidated, .biometryNotSetUp])
    func deviceThatCantSignSaysSoBeforeAnyoneIsPicked(availability: SigningAvailability) async {
        let repository = FakeTransfersRepository(clock: clock)
        let signer = FakeSigner()
        await signer.set(availability: availability)
        let router = TransferRouter()
        let viewModel = RecipientsViewModel(
            source: Sample.account,
            dependencies: dependencies(repository: repository, signer: signer, clock: clock),
            router: router,
            onSessionExpired: {}
        )

        await viewModel.onAppear()

        #expect(router.signingIssue == availability)
        #expect(viewModel.state.recipients.isEmpty)
    }

    @Test func signInAgainGoesStraightOutWhenNothingIsPending() async {
        let outputs = Outputs()
        let viewModel = SigningIssueViewModel(
            issue: .keyInvalidated,
            dependencies: dependencies(repository: FakeTransfersRepository(clock: clock), clock: clock),
            onSignInAgain: outputs.finish
        )

        await viewModel.signInAgain()

        #expect(outputs.finished == 1)
        #expect(viewModel.state.title == TransferStrings.keyInvalidatedTitle)
    }

    /// A transfer is still in the outbox: signing out would cancel it, so ask first.
    @Test func pendingTransferIsConfirmedBeforeSigningOut() async {
        let outputs = Outputs()
        let outbox = FakeOutbox()
        await outbox.setPending(true)
        let viewModel = SigningIssueViewModel(
            issue: .biometryNotSetUp,
            dependencies: dependencies(repository: FakeTransfersRepository(clock: clock), outbox: outbox, clock: clock),
            onSignInAgain: outputs.finish
        )

        await viewModel.signInAgain()
        #expect(viewModel.state.confirmsSignOut)
        #expect(outputs.finished == 0)

        viewModel.cancelSignOut()
        #expect(outputs.finished == 0)

        await viewModel.signInAgain()
        viewModel.confirmSignOut()
        #expect(outputs.finished == 1)
    }
}
