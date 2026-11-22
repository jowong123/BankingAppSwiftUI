import DesignSystem
import SwiftUI

struct CreatePINView: View {
    let viewModel: CreatePINViewModel
    @State private var submission: PINSubmission?

    var body: some View {
        VStack(spacing: Spacing.xLarge) {
            Text(viewModel.state.step == .enter ? AuthStrings.createPINEnter : AuthStrings.createPINConfirm)
                .font(Typography.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityIdentifier("auth.createPIN.prompt")
            if let error = viewModel.state.error {
                AuthErrorText(error: error)
            }
            PINPad { pin in
                submission = PINSubmission(pin: pin)
            }
            .disabled(viewModel.state.isSaving)
        }
        .padding(Spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
        .navigationTitle(AuthStrings.createPINTitle)
        .task(id: submission) {
            if let submission {
                await viewModel.entered(submission.pin)
            }
        }
    }
}

#if DEBUG
    #Preview("Light") {
        NavigationStack {
            CreatePINView(viewModel: .preview())
        }
    }

    #Preview("Dark") {
        NavigationStack {
            CreatePINView(viewModel: .preview())
        }
        .preferredColorScheme(.dark)
    }

    #Preview("Accessibility 5") {
        NavigationStack {
            CreatePINView(viewModel: .preview())
        }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
    }

    extension CreatePINViewModel {
        static func preview() -> CreatePINViewModel {
            CreatePINViewModel(dependencies: AuthDependencies(session: PreviewSession()), onSessionChange: { _ in })
        }
    }
#endif
