import DesignSystem
import Domain
import SwiftUI

/// The fee breakdown and countdown, then Send (SPEC section 5: Quoted, Expired).
struct ReviewView: View {
    let viewModel: ReviewViewModel
    @Environment(\.locale) private var locale
    @State private var sendRequests = 0
    @State private var retryRequests = 0

    var body: some View {
        let state = viewModel.state
        VStack(alignment: .leading, spacing: Spacing.xLarge) {
            breakdown(state.quote)
            countdown
            if state.rateUpdated {
                rateUpdatedNotice
            }
            if let error = state.error {
                MessageView(error: error) {
                    retryRequests += 1
                }
            }
            Spacer()
            PrimaryButton(TransferStrings.send, isLoading: state.isSending) {
                sendRequests += 1
            }
            .disabled(!state.canSend)
            .accessibilityIdentifier("transfer.review.send")
        }
        .padding(Spacing.large)
        .background(Palette.background)
        .navigationTitle(TransferStrings.reviewTitle)
        .inlineNavigationTitle()
        // Restarts with each new quote; cancelled when the screen goes away.
        .task(id: state.quote.id) {
            await viewModel.runCountdown()
        }
        .task(id: sendRequests) {
            if sendRequests > 0 {
                await viewModel.send()
            }
        }
        .task(id: retryRequests) {
            if retryRequests > 0 {
                await viewModel.retry()
            }
        }
    }

    private func breakdown(_ quote: FXQuote) -> some View {
        VStack(spacing: Spacing.medium) {
            row(TransferStrings.reviewYouSend, AmountText(quote.sourceAmount))
            row(TransferStrings.fee, AmountText(quote.fee))
            row(
                TransferStrings.rate,
                Text(TransferStrings.rate(quote.rate))
            )
            Divider()
            row(TransferStrings.theyReceive(viewModel.recipient.name), AmountText(quote.targetAmount, style: .hero))
                .accessibilityIdentifier("transfer.review.receive")
        }
        .padding(Spacing.large)
        .background(RoundedRectangle(cornerRadius: Radius.card).fill(Palette.surface))
    }

    private func row(_ label: String, _ value: some View) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            value
                .foregroundStyle(Palette.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var countdown: some View {
        Group {
            if viewModel.state.isRequoting {
                Text(TransferStrings.requoting)
            } else {
                Text(TransferStrings.countdown(seconds: viewModel.state.secondsLeft))
                    .monospacedDigit()
            }
        }
        .font(Typography.caption)
        .foregroundStyle(Palette.textSecondary)
        .accessibilityIdentifier("transfer.review.countdown")
    }

    private var rateUpdatedNotice: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(TransferStrings.rateUpdatedTitle)
                .font(Typography.bodyEmphasised)
                .accessibilityIdentifier("transfer.review.rateUpdated")
            Text(TransferStrings.rateUpdatedMessage)
                .font(Typography.caption)
            Button(TransferStrings.rateUpdatedOK) {
                viewModel.acknowledgeNewRate()
            }
            .accessibilityIdentifier("transfer.review.rateUpdated.ok")
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(Palette.surfaceElevated))
    }
}

#if DEBUG
    #Preview("Light") {
        NavigationStack {
            ReviewView(viewModel: .preview)
        }
    }

    #Preview("Dark") {
        NavigationStack {
            ReviewView(viewModel: .preview)
        }
        .preferredColorScheme(.dark)
    }

    #Preview("Accessibility 5") {
        NavigationStack {
            ReviewView(viewModel: .preview)
        }
        .dynamicTypeSize(.accessibility5)
    }

    extension ReviewViewModel {
        static var preview: ReviewViewModel {
            ReviewViewModel(
                source: PreviewTransfers.account,
                recipient: PreviewTransfers.recipient,
                quote: PreviewTransfers.quote(),
                dependencies: PreviewTransfers.dependencies,
                router: TransferRouter(),
                onSessionExpired: {}
            )
        }
    }
#endif
