import DesignSystem
import Domain
import SwiftUI

/// Who to send to.
struct RecipientsView: View {
    let viewModel: RecipientsViewModel
    @State private var retryRequests = 0

    var body: some View {
        List {
            if let error = viewModel.state.error {
                MessageView(error: error) {
                    retryRequests += 1
                }
            }
            if viewModel.state.showsEmpty {
                Text(TransferStrings.noRecipients)
                    .foregroundStyle(Palette.textSecondary)
            }
            ForEach(viewModel.state.recipients) { recipient in
                Button {
                    viewModel.select(recipient)
                } label: {
                    RecipientRow(recipient: recipient)
                }
                .accessibilityIdentifier("transfer.recipient.\(recipient.id)")
            }
        }
        .groupedListStyle()
        .overlay {
            if viewModel.state.isLoading && !viewModel.state.hasLoaded {
                ProgressView()
            }
        }
        .navigationTitle(TransferStrings.recipientsTitle)
        .inlineNavigationTitle()
        .task(id: retryRequests) {
            if retryRequests == 0 {
                await viewModel.onAppear()
            } else {
                await viewModel.retry()
            }
        }
    }
}

private struct RecipientRow: View {
    let recipient: Recipient

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(recipient.name)
                .font(Typography.bodyEmphasised)
                .foregroundStyle(Palette.textPrimary)
            Text(TransferStrings.recipientSubtitle(currency: recipient.currency, last4: recipient.accountLast4))
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.vertical, Spacing.xSmall)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
    #Preview("Light") {
        NavigationStack {
            RecipientsView(viewModel: .preview)
        }
    }

    #Preview("Dark") {
        NavigationStack {
            RecipientsView(viewModel: .preview)
        }
        .preferredColorScheme(.dark)
    }

    #Preview("Accessibility 5") {
        NavigationStack {
            RecipientsView(viewModel: .preview)
        }
        .dynamicTypeSize(.accessibility5)
    }

    extension RecipientsViewModel {
        static var preview: RecipientsViewModel {
            RecipientsViewModel(
                source: PreviewTransfers.account,
                dependencies: PreviewTransfers.dependencies,
                router: TransferRouter(),
                onSessionExpired: {}
            )
        }
    }
#endif
