import DesignSystem
import Domain
import SwiftUI

/// "Face ID changed" or "Set up Face ID", with the way out: sign in again.
struct SigningIssueView: View {
    let viewModel: SigningIssueViewModel
    let onClose: () -> Void
    @State private var signInRequests = 0

    var body: some View {
        let state = viewModel.state
        VStack(alignment: .leading, spacing: Spacing.large) {
            Image(systemName: "faceid")
                .font(.largeTitle)
                .foregroundStyle(Palette.textSecondary)
                .accessibilityHidden(true)
            Text(state.title)
                .font(Typography.title)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("transfer.signing.title")
            Text(state.message)
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            PrimaryButton(TransferStrings.signInAgain) {
                signInRequests += 1
            }
            .accessibilityIdentifier("transfer.signing.signInAgain")
            Button(TransferStrings.close, action: onClose)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("transfer.signing.close")
        }
        .padding(Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.background)
        .task(id: signInRequests) {
            if signInRequests > 0 {
                await viewModel.signInAgain()
            }
        }
        .alert(
            TransferStrings.pendingSignOutTitle,
            isPresented: Binding(
                get: {
                    viewModel.state.confirmsSignOut
                },
                set: { shown in
                    if !shown {
                        viewModel.cancelSignOut()
                    }
                }
            )
        ) {
            Button(TransferStrings.pendingSignOutConfirm, role: .destructive) {
                viewModel.confirmSignOut()
            }
            Button(TransferStrings.cancel, role: .cancel) {
                viewModel.cancelSignOut()
            }
        } message: {
            Text(TransferStrings.pendingSignOutMessage)
        }
    }
}

#if DEBUG
    #Preview("Face ID changed") {
        SigningIssueView(
            viewModel: SigningIssueViewModel(
                issue: .keyInvalidated, dependencies: PreviewTransfers.dependencies, onSignInAgain: {}),
            onClose: {}
        )
    }

    #Preview("No Face ID, Accessibility 5") {
        SigningIssueView(
            viewModel: SigningIssueViewModel(
                issue: .biometryNotSetUp, dependencies: PreviewTransfers.dependencies, onSignInAgain: {}),
            onClose: {}
        )
        .dynamicTypeSize(.accessibility5)
        .preferredColorScheme(.dark)
    }
#endif
