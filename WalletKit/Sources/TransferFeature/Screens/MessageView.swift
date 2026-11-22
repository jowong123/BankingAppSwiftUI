import DesignSystem
import Domain
import SwiftUI

/// An error in place: title, what to do, and Retry when it can help. `onRetry` only
/// records the request; the screen's `.task(id:)` runs it.
struct MessageView: View {
    let error: UserFacingError
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(error.title)
                .font(Typography.bodyEmphasised)
                .accessibilityIdentifier("transfer.error.title")
            Text(error.message)
                .font(Typography.caption)
            if error.canRetry, let onRetry {
                Button(TransferStrings.retry, action: onRetry)
                    .accessibilityIdentifier("transfer.retry")
            }
        }
        .foregroundStyle(Palette.negative)
    }
}
