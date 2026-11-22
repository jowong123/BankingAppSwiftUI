import Foundation

/// Integer minor-unit arithmetic. Amounts never pass through `Double`.
enum MoneyMath {
    /// Fee in source minor units: 0.5% rounded up, at least 1 major unit's worth for
    /// 0-decimal currencies or 100 minor units otherwise. Charged in the source currency
    /// and deducted before conversion (SPEC section 5).
    static func fee(sourceMinor: Int64, currency: String) -> Int64 {
        let minimum: Int64 = Currencies.minorUnits[currency] == 0 ? 1 : 100
        let percentage = (sourceMinor * 50 + 9_999) / 10_000  // ceil(source * 0.5%)
        return max(minimum, percentage)
    }

    /// `round((sourceMinor - feeMinor) * rate)`, converted between the two currencies'
    /// minor units, with banker's rounding like the app's `Money`.
    static func convert(
        netSourceMinor: Int64,
        sourceCurrency: String,
        targetCurrency: String,
        rate: Decimal
    ) -> Int64? {
        guard let sourceUnits = Currencies.minorUnits[sourceCurrency],
            let targetUnits = Currencies.minorUnits[targetCurrency]
        else {
            return nil
        }
        let sourceMajor = Decimal(netSourceMinor) / power(sourceUnits)
        let targetMinor = round(sourceMajor * rate * power(targetUnits), scale: 0)
        // Rounded to scale 0, so the description is plain digits; nil if it overflows Int64.
        return Int64(targetMinor.description)
    }

    static func round(_ value: Decimal, scale: Int) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .bankers)
        return result
    }

    private static func power(_ exponent: Int) -> Decimal {
        Decimal(sign: .plus, exponent: exponent, significand: 1)
    }
}
