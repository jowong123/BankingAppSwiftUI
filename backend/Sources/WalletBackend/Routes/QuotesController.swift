import SQLKit
import Vapor

struct QuotesController: Sendable {
    static let lifetimeMillis: Int64 = 30_000
    /// 10 billion minor units: far above any sandbox balance, far below Int64 overflow.
    static let maxSourceMinor: Int64 = 10_000_000_000

    let clock: BackendClock
    let rates: RateTable

    /// Fee in the source currency, deducted before conversion (SPEC section 5):
    /// `target = round((source - fee) * rate)`. Valid for 30 seconds.
    @Sendable func create(_ request: Request) async throws -> Response {
        let user = try request.auth.require(AuthenticatedUser.self)
        let body = try request.content.decode(QuoteRequest.self)
        let source = body.sourceAmount
        guard Currencies.isSupported(source.currency), Currencies.isSupported(body.targetCurrency) else {
            throw APIFailure.invalid("Currency is not supported.")
        }
        guard source.currency != body.targetCurrency else {
            throw APIFailure.invalid("Source and target currency must differ.")
        }
        guard source.amountMinor > 0, source.amountMinor <= Self.maxSourceMinor else {
            throw APIFailure.invalid("Amount is out of range.")
        }
        let fee = MoneyMath.fee(sourceMinor: source.amountMinor, currency: source.currency)
        guard source.amountMinor > fee else {
            throw APIFailure.invalid("Amount must be more than the fee.")
        }
        guard let rate = rates.rate(from: source.currency, to: body.targetCurrency),
            let target = MoneyMath.convert(
                netSourceMinor: source.amountMinor - fee,
                sourceCurrency: source.currency,
                targetCurrency: body.targetCurrency,
                rate: rate
            ),
            target > 0
        else {
            throw APIFailure.invalid("Amount is too small to convert.")
        }

        let row = QuoteRow(
            id: "q_\(UUID().uuidString.lowercased())",
            userId: user.id,
            sourceMinor: source.amountMinor,
            sourceCurrency: source.currency,
            targetMinor: target,
            targetCurrency: body.targetCurrency,
            feeMinor: fee,
            rate: rate.description,
            expiresAt: clock.nowMillis + Self.lifetimeMillis
        )
        try await request.sql.insert(into: "quotes").model(row).run()
        return try await QuoteDTO(row).encodeResponse(status: .created, for: request)
    }
}
