import Foundation

/// Currencies the sandbox supports, with ISO 4217 minor units. Must match the app's
/// `Currency.supported` table.
enum Currencies {
    static let minorUnits: [String: Int] = ["SGD": 2, "USD": 2, "EUR": 2, "JPY": 0, "KWD": 3]

    static func isSupported(_ code: String) -> Bool { minorUnits[code] != nil }
}

/// Simulated FX: units of each currency per 1 USD. The live table jitters each quote
/// slightly so the app's "rate updated" path is visible; tests use fixed rates.
struct RateTable: Sendable {
    let perUSD: @Sendable (String) -> Decimal?

    static let base: [String: Decimal] = [
        "USD": 1,
        "SGD": Decimal(string: "1.3412") ?? 1,
        "EUR": Decimal(string: "0.9234") ?? 1,
        "JPY": Decimal(string: "151.27") ?? 1,
        "KWD": Decimal(string: "0.3071") ?? 1,
    ]

    static let fixed = RateTable { base[$0] }

    /// ±0.2% random wobble per quote.
    static let live = RateTable { code in
        guard let rate = base[code] else { return nil }
        let wobble = Decimal(Int.random(in: -20...20)) / 10_000
        return rate * (1 + wobble)
    }

    /// Units of `target` per 1 unit of `source`, rounded to 8 decimal places.
    func rate(from source: String, to target: String) -> Decimal? {
        guard let sourcePerUSD = perUSD(source), let targetPerUSD = perUSD(target), sourcePerUSD > 0 else {
            return nil
        }
        return MoneyMath.round(targetPerUSD / sourcePerUSD, scale: 8)
    }
}

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
        else { return nil }
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
