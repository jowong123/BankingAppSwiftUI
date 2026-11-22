import DesignSystem
import SwiftUI

struct SignInView: View {
    let viewModel: SignInViewModel
    /// Bumped by the button. The `.task(id:)` below does the work, so it is cancelled with the screen.
    @State private var submitRequests = 0

    var body: some View {
        Form {
            if let notice = viewModel.state.notice {
                Section {
                    Text(notice)
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityIdentifier("auth.notice")
                }
            }
            Section {
                TextField(AuthStrings.email, text: email)
                    .emailField()
                    .accessibilityIdentifier("auth.email")
                SecureField(AuthStrings.password, text: password)
                    .passwordField()
                    .onSubmit {
                        submitRequests += 1
                    }
                    .accessibilityIdentifier("auth.password")
            } footer: {
                if let error = viewModel.state.error {
                    AuthErrorText(error: error, alignment: .leading)
                }
            }
            Section {
                PrimaryButton(AuthStrings.signIn, isLoading: viewModel.state.isSubmitting) {
                    submitRequests += 1
                }
                .disabled(!viewModel.state.canSubmit)
                .accessibilityIdentifier("auth.submit")
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(AuthStrings.signInTitle)
        .task(id: submitRequests) {
            if submitRequests > 0 {
                await viewModel.submit()
            }
        }
    }

    private var email: Binding<String> {
        Binding(
            get: {
                viewModel.state.email
            },
            set: {
                viewModel.setEmail($0)
            }
        )
    }

    private var password: Binding<String> {
        Binding(
            get: {
                viewModel.password
            },
            set: {
                viewModel.setPassword($0)
            }
        )
    }
}

#if DEBUG
    #Preview("Light") {
        NavigationStack {
            SignInView(viewModel: .preview(notice: nil))
        }
    }

    #Preview("Dark") {
        NavigationStack {
            SignInView(viewModel: .preview(notice: .sessionExpired))
        }
        .preferredColorScheme(.dark)
    }

    #Preview("Accessibility 5") {
        NavigationStack {
            SignInView(viewModel: .preview(notice: nil))
        }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
    }

    extension SignInViewModel {
        static func preview(notice: SignInNotice?) -> SignInViewModel {
            SignInViewModel(
                notice: notice,
                dependencies: AuthDependencies(session: PreviewSession()),
                onSessionChange: { _ in }
            )
        }
    }
#endif
