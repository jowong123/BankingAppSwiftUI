import Domain
import SwiftUI

/// Displays a `Money` value with locale formatting and a VoiceOver label that
/// spells out the currency. Colour is inherited, so callers set `foregroundStyle`.
public struct AmountText: View {
    public enum Style: Sendable {
        /// The large balance figure at the top of a screen.
        case hero
        /// An amount inside a row or card.
        case row
    }

    private let money: Money
    private let style: Style
    private let showsPlusSign: Bool
    @Environment(\.locale) private var locale

    public init(_ money: Money, style: Style = .row, showsPlusSign: Bool = false) {
        self.money = money
        self.style = style
        self.showsPlusSign = showsPlusSign
    }

    public var body: some View {
        Text(prefix + money.formatted(locale: locale))
            .font(style == .hero ? Typography.balance : Typography.amount)
            // A hero balance shrinks rather than wraps mid-number at large text sizes.
            .lineLimit(style == .hero ? 1 : nil)
            .minimumScaleFactor(style == .hero ? 0.5 : 1)
            .accessibilityLabel(prefix + money.accessibilityLabel(locale: locale))
    }

    private var prefix: String {
        Self.prefix(for: money, showsPlusSign: showsPlusSign)
    }

    /// "+" only for a positive amount, so zero and negatives never read as "+0" or "+-5".
    static func prefix(for money: Money, showsPlusSign: Bool) -> String {
        showsPlusSign && !money.isNegative && !money.isZero ? "+" : ""
    }
}

#Preview("Light") {
    AmountPreview()
}

#Preview("Dark") {
    AmountPreview()
        .preferredColorScheme(.dark)
}

#Preview("Accessibility 5") {
    AmountPreview()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

private struct AmountPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            AmountText(Money(amountMinor: 1_025_000, currency: .usd), style: .hero)
            AmountText(Money(amountMinor: 1_234_567, currency: .jpy))
            AmountText(Money(amountMinor: 820_050, currency: .sgd))
            AmountText(Money(amountMinor: 1_500, currency: .kwd))
            AmountText(Money(amountMinor: 14_000, currency: .usd), showsPlusSign: true)
                .foregroundStyle(Palette.positive)
        }
        .foregroundStyle(Palette.textPrimary)
        .padding(Spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.background)
    }
}
