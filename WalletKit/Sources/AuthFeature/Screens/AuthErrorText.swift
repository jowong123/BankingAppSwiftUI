import DesignSystem
import Domain
import SwiftUI

/// An auth error shown in place: the title, then what to do. The message line carries the
/// identifier, so UI tests can wait on it.
struct AuthErrorText: View {
    let error: UserFacingError
    var alignment = HorizontalAlignment.center
    var messageIdentifier = "auth.error"

    var body: some View {
        VStack(alignment: alignment, spacing: Spacing.xSmall) {
            Text(error.title)
                .font(Typography.bodyEmphasised)
                .accessibilityIdentifier("auth.error.title")
            Text(error.message)
                .font(Typography.caption)
                .accessibilityIdentifier(messageIdentifier)
        }
        .foregroundStyle(Palette.negative)
        .multilineTextAlignment(alignment == .leading ? .leading : .center)
    }
}
