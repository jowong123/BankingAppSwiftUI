import Domain
import SwiftUI

/// A large amount input with a currency chip. Produces `Money` (never `Double`), and
/// limits decimals to the currency's minor units: none for JPY, three for KWD.
public struct AmountField: View {
    private let label: String
    private let currency: Currency
    @Binding private var amount: Money?
    @State private var text = ""
    @Environment(\.locale) private var locale

    /// - Parameter label: shown above the field and read by VoiceOver, e.g. "You send".
    public init(_ label: String, currency: Currency, amount: Binding<Money?>) {
        self.label = label
        self.currency = currency
        self._amount = amount
    }

    private var filter: AmountInputFilter {
        AmountInputFilter(currency: currency, locale: locale)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
                .accessibilityHidden(true)  // The text field carries the label for VoiceOver.

            HStack(spacing: Spacing.medium) {
                TextField("0", text: $text)
                    .font(Typography.balance)
                    .foregroundStyle(Palette.textPrimary)
                    .amountKeyboard(allowsDecimals: currency.minorUnits > 0)
                    .accessibilityLabel(label)
                    .accessibilityValue(amount.map { $0.accessibilityLabel(locale: locale) } ?? "")

                Text(currency.code)
                    .font(Typography.headline)
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, Spacing.medium)
                    .padding(.vertical, Spacing.small)
                    .background(Capsule().fill(Palette.surfaceElevated))
                    .accessibilityHidden(true)  // The value label already names the currency.
            }
        }
        .padding(Spacing.large)
        .background(RoundedRectangle(cornerRadius: Radius.card).fill(Palette.surface))
        // Prefill in onAppear, not init, so it uses the environment locale like editing does.
        .onAppear { text = filter.text(for: amount) }
        .onChange(of: text) { _, newText in
            let clean = filter.sanitize(newText)
            // Rewriting `text` re-enters onChange once, then `clean == newText` stops it.
            if clean != newText { text = clean }
            amount = filter.money(from: clean)
        }
        // The parent can also set the amount (a reset, or a re-quoted "recipient gets").
        // Only rewrite the text when it disagrees, so "12," isn't replaced with "12" mid-typing.
        .onChange(of: amount) { _, newAmount in
            if filter.money(from: text) != newAmount { text = filter.text(for: newAmount) }
        }
        .onChange(of: currency) {
            text = filter.sanitize(text)
            amount = filter.money(from: text)
        }
    }
}

extension View {
    @ViewBuilder
    fileprivate func amountKeyboard(allowsDecimals: Bool) -> some View {
        #if os(iOS)
            keyboardType(allowsDecimals ? .decimalPad : .numberPad)
        #else
            self
        #endif
    }
}

#Preview("Light") {
    AmountFieldPreview()
}

#Preview("Dark") {
    AmountFieldPreview()
        .preferredColorScheme(.dark)
}

#Preview("Accessibility 5") {
    AmountFieldPreview()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

private struct AmountFieldPreview: View {
    @State private var send: Money? = Money(amountMinor: 100_000, currency: .sgd)
    @State private var yen: Money?
    @State private var dinar: Money?

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.large) {
                AmountField("You send", currency: .sgd, amount: $send)
                AmountField("Recipient gets", currency: .jpy, amount: $yen)
                AmountField("Recipient gets", currency: .kwd, amount: $dinar)
            }
            .padding(Spacing.large)
        }
        .background(Palette.background)
    }
}
