import DesignSystem
import Domain
import SwiftUI

/// How much to send. Continue gets a quote and opens the review.
struct AmountView: View {
    let viewModel: AmountViewModel
    @Environment(\.locale) private var locale
    @State private var continueRequests = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xLarge) {
            AmountField(
                TransferStrings.youSend,
                currency: viewModel.source.currency,
                amount: Binding(
                    get: {
                        viewModel.state.amount
                    },
                    set: {
                        viewModel.setAmount($0)
                    })
            )
            .accessibilityIdentifier("transfer.amount")
            Text(TransferStrings.available(viewModel.source.balance.formatted(locale: locale)))
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
            if viewModel.state.exceedsBalance {
                Text(TransferStrings.tooMuch)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.negative)
            }
            if let error = viewModel.state.error {
                MessageView(error: error)
            }
            Spacer()
            PrimaryButton(TransferStrings.continueTitle, isLoading: viewModel.state.isQuoting) {
                continueRequests += 1
            }
            .disabled(!viewModel.state.canContinue)
            .accessibilityIdentifier("transfer.continue")
        }
        .padding(Spacing.large)
        .background(Palette.background)
        .navigationTitle(viewModel.recipient.name)
        .inlineNavigationTitle()
        .task(id: continueRequests) {
            if continueRequests > 0 {
                await viewModel.continueTapped()
            }
        }
    }
}

#if DEBUG
    #Preview("Light") {
        NavigationStack {
            AmountView(viewModel: .preview)
        }
    }

    #Preview("Dark") {
        NavigationStack {
            AmountView(viewModel: .preview)
        }
        .preferredColorScheme(.dark)
    }

    #Preview("Accessibility 5") {
        NavigationStack {
            AmountView(viewModel: .preview)
        }
        .dynamicTypeSize(.accessibility5)
    }

    extension AmountViewModel {
        static var preview: AmountViewModel {
            AmountViewModel(
                source: PreviewTransfers.account,
                recipient: PreviewTransfers.recipient,
                dependencies: PreviewTransfers.dependencies,
                router: TransferRouter(),
                onSessionExpired: {}
            )
        }
    }
#endif
