import DesignSystem
import Domain
import SwiftUI

/// Currency name and code on top, the balance below.
struct AccountCard: View {
    let account: Account
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack {
                Text(currencyName)
                    .font(Typography.headline)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Text(account.currency.code)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityHidden(true)
            }
            AmountText(account.balance, style: .hero)
                .foregroundStyle(Palette.textPrimary)
        }
        .padding(.vertical, Spacing.small)
        // One VoiceOver stop per card: the currency name, then the amount read out in
        // words with its currency ("12,500.00 Singapore dollars").
        .accessibilityElement(children: .combine)
    }

    private var currencyName: String {
        locale.localizedString(forCurrencyCode: account.currency.code) ?? account.currency.code
    }
}
