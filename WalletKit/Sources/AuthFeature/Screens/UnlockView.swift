import DesignSystem
import SwiftUI

struct UnlockView: View {
    let viewModel: UnlockViewModel
    @State private var submission: PINSubmission?
    @State private var biometricRequests = 0
    @State private var signOutRequests = 0
    @State private var confirmedSignOuts = 0

    var body: some View {
        VStack(spacing: Spacing.xLarge) {
            Text(AuthStrings.unlockTitle)
                .font(Typography.title)
                .foregroundStyle(Palette.textPrimary)
            if let error = viewModel.state.error {
                AuthErrorText(error: error, messageIdentifier: "auth.unlock.message")
            } else {
                Text(AuthStrings.unlockPrompt)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityIdentifier("auth.unlock.message")
            }
            PINPad { pin in
                submission = PINSubmission(pin: pin)
            }
            .disabled(viewModel.state.isChecking)
            HStack(spacing: Spacing.xLarge) {
                if viewModel.state.canUseBiometrics {
                    Button(AuthStrings.useFaceID) {
                        biometricRequests += 1
                    }
                    .accessibilityIdentifier("auth.unlock.faceID")
                }
                Button(AuthStrings.signOut, role: .destructive) {
                    signOutRequests += 1
                }
                .accessibilityIdentifier("auth.unlock.signOut")
            }
        }
        .padding(Spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
        .alert(
            AuthStrings.tooManyAttemptsTitle,
            isPresented: Binding(
                get: {
                    viewModel.state.showsTooManyAttempts
                },
                set: { _ in
                }
            )
        ) {
            Button(AuthStrings.okay) {
                viewModel.acknowledgeSignedOut()
            }
        } message: {
            Text(AuthStrings.tooManyAttemptsMessage)
        }
        .alert(
            AuthStrings.pendingTransferTitle,
            isPresented: Binding(
                get: {
                    viewModel.state.confirmsSignOut
                },
                set: { _ in
                }
            )
        ) {
            Button(AuthStrings.signOut, role: .destructive) {
                confirmedSignOuts += 1
            }
            Button(AuthStrings.staySignedIn, role: .cancel) {
                viewModel.cancelSignOut()
            }
        } message: {
            Text(AuthStrings.pendingTransferMessage)
        }
        .task {
            await viewModel.onAppear()
        }
        .task(id: confirmedSignOuts) {
            if confirmedSignOuts > 0 {
                await viewModel.confirmSignOut()
            }
        }
        .task(id: submission) {
            if let submission {
                await viewModel.entered(submission.pin)
            }
        }
        .task(id: biometricRequests) {
            if biometricRequests > 0 {
                await viewModel.unlockWithBiometrics()
            }
        }
        .task(id: signOutRequests) {
            if signOutRequests > 0 {
                await viewModel.signOut()
            }
        }
    }
}

#if DEBUG
    #Preview("Light") {
        UnlockView(viewModel: .preview())
    }

    #Preview("Dark") {
        UnlockView(viewModel: .preview())
            .preferredColorScheme(.dark)
    }

    #Preview("Accessibility 5") {
        UnlockView(viewModel: .preview())
            .preferredColorScheme(.dark)
            .dynamicTypeSize(.accessibility5)
    }

    extension UnlockViewModel {
        static func preview() -> UnlockViewModel {
            UnlockViewModel(dependencies: AuthDependencies(session: PreviewSession()), onSessionChange: { _ in })
        }
    }
#endif
