import Foundation

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

    static let fixed = RateTable {
        base[$0]
    }

    /// ±0.2% random wobble per quote.
    static let live = RateTable { code in
        guard let rate = base[code] else {
            return nil
        }
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
