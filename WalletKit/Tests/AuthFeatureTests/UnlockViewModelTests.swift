import Domain
import Testing

@testable import AuthFeature

@MainActor
@Suite struct UnlockViewModelTests {
    let session = FakeSession()
    let changes = SessionChanges()

    func makeViewModel() -> UnlockViewModel {
        UnlockViewModel(
            dependencies: AuthDependencies(session: session),
            onSessionChange: { [changes] in
                changes.record($0)
            }
        )
    }

    @Test func offersFaceIDOnAppearWhenAvailable() async {
        let viewModel = makeViewModel()

        await viewModel.onAppear()

        #expect(await session.calls == ["biometrics"])
        #expect(changes.states == [.unlocked])
    }

    @Test func withoutFaceIDGoesStraightToThePIN() async {
        await session.set(biometrics: .success(.unlocked), available: false)
        let viewModel = makeViewModel()

        await viewModel.onAppear()

        #expect(await session.calls.isEmpty)
        #expect(!viewModel.state.canUseBiometrics)
    }

    @Test func offersFaceIDOnlyOnce() async {
        await session.set(biometrics: .failure(.cancelled))
        let viewModel = makeViewModel()

        await viewModel.onAppear()
        await viewModel.onAppear()

        #expect(await session.calls == ["biometrics"])
    }

    @Test func cancellingFaceIDShowsNoError() async {
        await session.set(biometrics: .failure(.cancelled))
        let viewModel = makeViewModel()

        await viewModel.onAppear()

        #expect(viewModel.state.error == nil)
        #expect(changes.states.isEmpty)
    }

    @Test func failedFaceIDPointsToThePIN() async {
        await session.set(biometrics: .failure(.biometryFailed))
        let viewModel = makeViewModel()

        await viewModel.onAppear()

        #expect(viewModel.state.error?.title == AuthStrings.biometryFailedTitle)
        #expect(viewModel.state.error?.message == "Enter your PIN.")
    }

    @Test func rightPINUnlocks() async {
        let viewModel = makeViewModel()

        await viewModel.entered("123456")

        #expect(changes.states == [.unlocked])
    }

    @Test(arguments: [(4, "4 attempts left."), (1, "1 attempt left before you're signed out.")])
    func wrongPINSaysHowManyAttemptsAreLeft(attemptsLeft: Int, message: String) async {
        await session.set(unlock: .failure(.wrongPIN(attemptsLeft: attemptsLeft)))
        let viewModel = makeViewModel()

        await viewModel.entered("000000")

        #expect(viewModel.state.error?.title == "Wrong PIN")
        #expect(viewModel.state.error?.message == message)
        #expect(changes.states.isEmpty)
    }

    @Test func tooManyAttemptsExplainsThenSignsOut() async {
        await session.set(unlock: .failure(.tooManyAttempts))
        let viewModel = makeViewModel()

        await viewModel.entered("000000")

        #expect(viewModel.state.showsTooManyAttempts)
        #expect(changes.states.isEmpty)

        viewModel.acknowledgeSignedOut()

        #expect(changes.states == [.signedOut])
        #expect(!viewModel.state.showsTooManyAttempts)
    }

    @Test func noMorePINsAfterTheLastAttempt() async {
        await session.set(unlock: .failure(.tooManyAttempts))
        let viewModel = makeViewModel()
        await viewModel.entered("000000")

        await viewModel.entered("123456")

        #expect(await session.calls == ["unlock"])
    }

    /// Signing out deletes the outbox: with a transfer still sending, ask first.
    @Test func signOutWithAPendingTransferAsksFirst() async {
        let viewModel = UnlockViewModel(
            dependencies: AuthDependencies(
                session: session,
                hasPendingTransfers: {
                    true
                }),
            onSessionChange: { [changes] in
                changes.record($0)
            }
        )

        await viewModel.signOut()
        #expect(viewModel.state.confirmsSignOut)
        #expect(await session.calls.isEmpty)

        viewModel.cancelSignOut()
        #expect(!viewModel.state.confirmsSignOut)
        #expect(changes.states.isEmpty)

        await viewModel.signOut()
        await viewModel.confirmSignOut()
        #expect(await session.calls == ["signOut"])
        #expect(changes.states == [.signedOut])
    }

    @Test func signOutReportsSignedOut() async {
        let viewModel = makeViewModel()

        await viewModel.signOut()

        #expect(await session.calls == ["signOut"])
        #expect(changes.states == [.signedOut])
    }
}
