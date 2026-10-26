import Domain
import Testing

@testable import DesignSystem

@MainActor
@Suite struct AmountTextTests {
    @Test func plusSignOnlyForPositiveAmounts() {
        #expect(AmountText.prefix(for: Money(amountMinor: 14_000, currency: .usd), showsPlusSign: true) == "+")
        #expect(AmountText.prefix(for: Money.zero(.usd), showsPlusSign: true) == "")
        #expect(AmountText.prefix(for: Money(amountMinor: -500, currency: .usd), showsPlusSign: true) == "")
        #expect(AmountText.prefix(for: Money(amountMinor: 14_000, currency: .usd), showsPlusSign: false) == "")
    }
}
