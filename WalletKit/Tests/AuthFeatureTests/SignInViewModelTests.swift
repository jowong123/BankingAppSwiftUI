import Domain
import Testing

@testable import AuthFeature

@MainActor
@Suite struct SignInViewModelTests {
    let session = FakeSession()
    let changes = SessionChanges()

    func makeViewModel(notice: SignInNotice? = nil) -> SignInViewModel {
        SignInViewModel(
            notice: notice,
            dependencies: AuthDependencies(session: session),
            onSessionChange: { [changes] in
                changes.record($0)
            }
        )
    }

    @Test func needsAnEmailAndAPasswordToSubmit() {
        let viewModel = makeViewModel()
        #expect(!viewModel.state.canSubmit)

        viewModel.setEmail("  ")
        viewModel.setPassword("pw")
        #expect(!viewModel.state.canSubmit)

        viewModel.setEmail("demo@wallet.test")
        #expect(viewModel.state.canSubmit)
    }

    @Test func successReportsNeedsPINAndForgetsThePassword() async {
        let viewModel = makeViewModel()
        viewModel.setEmail("demo@wallet.test")
        viewModel.setPassword("pw")

        await viewModel.submit()

        #expect(changes.states == [.needsPIN])
        #expect(viewModel.password.isEmpty)
        #expect(!viewModel.state.hasPassword)
        #expect(viewModel.state.error == nil)
    }

    /// The password is never part of `State`, so a state dump or failing test can't print it.
    @Test func passwordIsNotInTheState() {
        let viewModel = makeViewModel()
        viewModel.setPassword("hunter2")

        #expect(!String(describing: viewModel.state).contains("hunter2"))
    }

    @Test func wrongPasswordShowsAnErrorAndClearsThePassword() async {
        await session.set(login: .failure(.invalidCredentials))
        let viewModel = makeViewModel()
        viewModel.setEmail("demo@wallet.test")
        viewModel.setPassword("bad")

        await viewModel.submit()

        #expect(viewModel.state.error?.message == "Email or password is incorrect.")
        #expect(viewModel.password.isEmpty)
        #expect(viewModel.state.email == "demo@wallet.test")
        #expect(changes.states.isEmpty)
    }

    @Test func offlineKeepsThePasswordSoTheUserCanRetry() async {
        await session.set(login: .failure(.offline))
        let viewModel = makeViewModel()
        viewModel.setEmail("demo@wallet.test")
        viewModel.setPassword("pw")

        await viewModel.submit()

        #expect(viewModel.state.error == AuthMessages.userFacing(.offline))
        #expect(viewModel.state.error?.canRetry == true)
        #expect(viewModel.password == "pw")
    }

    @Test func typingClearsTheError() async {
        await session.set(login: .failure(.offline))
        let viewModel = makeViewModel()
        viewModel.setEmail("demo@wallet.test")
        viewModel.setPassword("pw")
        await viewModel.submit()

        viewModel.setPassword("pw2")

        #expect(viewModel.state.error == nil)
    }

    @Test func sessionExpiredNoticeIsShown() {
        #expect(makeViewModel(notice: .sessionExpired).state.notice == AuthStrings.sessionExpired)
        #expect(makeViewModel().state.notice == nil)
    }

    @Test func emptyFormDoesNotCallTheServer() async {
        await makeViewModel().submit()

        #expect(await session.calls.isEmpty)
    }
}
