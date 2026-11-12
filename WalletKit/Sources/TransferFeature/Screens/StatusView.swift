import DesignSystem
import Domain
import SwiftUI

/// Where the transfer is: sending, on its way, sent or failed, with what was sent.
struct StatusView: View {
    let viewModel: StatusViewModel
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 64

    var body: some View {
        let state = viewModel.state
        VStack(spacing: Spacing.xLarge) {
            Spacer()
            icon
            Text(state.title)
                .font(Typography.title)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityIdentifier("transfer.status.title")
            Text(state.message)
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            if let quote = state.transfer?.draft.quote {
                AmountText(quote.targetAmount, style: .hero)
                    .foregroundStyle(Palette.textPrimary)
            }
            Spacer()
            PrimaryButton(TransferStrings.done) {
                viewModel.done()
            }
            .accessibilityIdentifier("transfer.status.done")
        }
        .padding(Spacing.large)
        .background(Palette.background)
        .navigationBarBackButtonHiddenOnIOS()
        .task {
            await viewModel.observe()
        }
    }

    @ViewBuilder private var icon: some View {
        switch viewModel.state.transfer?.state {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(Palette.positive)
                .accessibilityHidden(true)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(Palette.negative)
                .accessibilityHidden(true)
        default:
            ProgressView()
                .controlSize(.large)
        }
    }
}

#if DEBUG
    #Preview("Light") {
        NavigationStack {
            StatusView(viewModel: .preview)
        }
    }

    #Preview("Dark") {
        NavigationStack {
            StatusView(viewModel: .preview)
        }
        .preferredColorScheme(.dark)
    }

    #Preview("Accessibility 5") {
        NavigationStack {
            StatusView(viewModel: .preview)
        }
        .dynamicTypeSize(.accessibility5)
    }

    extension StatusViewModel {
        static var preview: StatusViewModel {
            StatusViewModel(
                transferID: PreviewTransfers.sentID, dependencies: PreviewTransfers.dependencies, onFinish: {})
        }
    }
#endif
