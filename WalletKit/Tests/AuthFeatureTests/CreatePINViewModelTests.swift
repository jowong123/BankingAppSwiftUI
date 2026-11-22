import Domain
import Testing

@testable import AuthFeature

@MainActor
@Suite struct CreatePINViewModelTests {
    let session = FakeSession()
    let changes = SessionChanges()

    func makeViewModel() -> CreatePINViewModel {
        CreatePINViewModel(
            dependencies: AuthDependencies(session: session),
            onSessionChange: { [changes] in
                changes.record($0)
            }
        )
    }

    @Test func firstEntryAsksForConfirmation() async {
        let viewModel = makeViewModel()

        await viewModel.entered("123456")

        #expect(viewModel.state.step == .confirm)
        #expect(await session.calls.isEmpty)
    }

    @Test func matchingConfirmationSavesThePINAndUnlocks() async {
        let viewModel = makeViewModel()

        await viewModel.entered("123456")
        await viewModel.entered("123456")

        #expect(await session.createdPIN == "123456")
        #expect(changes.states == [.unlocked])
    }

    @Test func mismatchStartsOverWithoutSaving() async {
        let viewModel = makeViewModel()

        await viewModel.entered("123456")
        await viewModel.entered("654321")

        #expect(viewModel.state.step == .enter)
        #expect(viewModel.state.error == AuthMessages.pinMismatch)
        #expect(await session.calls.isEmpty)
        #expect(changes.states.isEmpty)
    }

    @Test func saveFailureShowsAnErrorAndStartsOver() async {
        await session.set(createPIN: .failure(.storageUnavailable))
        let viewModel = makeViewModel()

        await viewModel.entered("123456")
        await viewModel.entered("123456")

        #expect(viewModel.state.step == .enter)
        #expect(viewModel.state.error?.title == AuthStrings.storageTitle)
        #expect(changes.states.isEmpty)
    }
}
