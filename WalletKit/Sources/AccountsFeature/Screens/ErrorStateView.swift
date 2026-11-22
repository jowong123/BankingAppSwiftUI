import Domain
import SwiftUI

/// Full-screen error with an optional Retry, used when there is nothing else to show.
/// `onRetry` only records the request; the screen's `.task(id:)` runs it.
struct ErrorStateView: View {
    let error: UserFacingError
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(error.title, systemImage: "wifi.exclamationmark")
        } description: {
            Text(error.message)
        } actions: {
            if error.canRetry {
                Button(AccountsStrings.retry, action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("accounts.retry")
            }
        }
    }
}
