import Domain
import SwiftUI

/// One line in a transaction list: avatar, title, subtitle and amount.
///
/// Takes plain values rather than a domain `Transaction` type, which doesn't exist
/// until Phase 4. Incoming amounts get a "+" and the positive colour.
public struct TransactionRow: View {
    public enum Direction: Sendable {
        case incoming
        case outgoing
    }

    private let title: String
    private let subtitle: String
    private let amount: Money
    private let direction: Direction
    private let initials: String?
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 44

    /// - Parameter initials: shown in the avatar; when nil an arrow shows the direction.
    public init(title: String, subtitle: String, amount: Money, direction: Direction, initials: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.amount = amount
        self.direction = direction
        self.initials = initials
    }

    public var body: some View {
        // At accessibility text sizes there isn't room for text and amount side by side,
        // so the amount drops below the title instead of truncating either.
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.small))
            : AnyLayout(HStackLayout(spacing: Spacing.medium))

        layout {
            HStack(spacing: Spacing.medium) {
                avatar
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    Text(title)
                        .font(Typography.bodyEmphasised)
                        .foregroundStyle(Palette.textPrimary)
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer(minLength: Spacing.small)
            AmountText(amount, showsPlusSign: direction == .incoming)
                .foregroundStyle(direction == .incoming ? Palette.positive : Palette.textPrimary)
        }
        .padding(.vertical, Spacing.small)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(Palette.surfaceElevated)
            if let initials {
                Text(initials)
                    .font(Typography.headline)
                    .foregroundStyle(Palette.textPrimary)
            } else {
                Image(systemName: direction == .incoming ? "arrow.down.left" : "arrow.up.right")
                    .font(Typography.headline)
                    .foregroundStyle(Palette.textPrimary)
            }
        }
        .frame(width: avatarSize, height: avatarSize)
    }

    private var accessibilityText: String {
        let sign = AmountText.prefix(for: amount, showsPlusSign: direction == .incoming)
        return "\(title), \(subtitle), \(sign)\(amount.accessibilityLabel(locale: locale))"
    }
}

#Preview("Light") {
    TransactionRowPreview()
}

#Preview("Dark") {
    TransactionRowPreview()
        .preferredColorScheme(.dark)
}

#Preview("Accessibility 5") {
    TransactionRowPreview()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

private struct TransactionRowPreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TransactionRow(
                    title: "Pull&Bear", subtitle: "Sunday",
                    amount: Money(amountMinor: 3_400, currency: .usd), direction: .outgoing, initials: "PB")
                TransactionRow(
                    title: "Robert Fox", subtitle: "Sunday",
                    amount: Money(amountMinor: 14_000, currency: .usd), direction: .incoming, initials: "RF")
                TransactionRow(
                    title: "Tokyo transfer", subtitle: "3 days ago",
                    amount: Money(amountMinor: 52_000, currency: .jpy), direction: .outgoing)
                TransactionRow(
                    title: "Salary", subtitle: "1 Oct",
                    amount: Money(amountMinor: 1_250_500, currency: .kwd), direction: .incoming)
            }
            .padding(Spacing.large)
            .background(RoundedRectangle(cornerRadius: Radius.card).fill(Palette.surface))
            .padding(Spacing.large)
        }
        .background(Palette.background)
    }
}
