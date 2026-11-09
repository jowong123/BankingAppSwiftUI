import DesignSystem
import SwiftUI

/// Covers the whole app whenever it isn't active, so the app switcher snapshot and anyone
/// glancing at a backgrounded app never see balances (SPEC section 4). Opaque rather than
/// a blur: a blur can still show the shape of large numbers.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(Palette.background)
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(Palette.textSecondary)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
