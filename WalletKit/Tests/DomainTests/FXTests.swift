import Foundation
import Testing

@testable import Domain

@Suite struct FXRateTests {
    @Test(arguments: ["0", "-1", "-0.0001"])
    func rejectsNonPositiveRate(rate: String) throws {
        let value = try decimal(rate)
        #expect(throws: MoneyError.invalidRate) {
            try FXRate(source: .sgd, target: .jpy, rate: value)
        }
    }

    @Test func rejectsNaNRate() {
        #expect(throws: MoneyError.invalidRate) {
            try FXRate(source: .sgd, target: .jpy, rate: .nan)
        }
    }

    /// Conversion rounds to the target currency, half to even.
    @Test(arguments: [
        (Currency.sgd, Currency.jpy, "110.456", "100", "11046"),
        (.sgd, .jpy, "0.5", "5", "2"),
        (.sgd, .jpy, "0.5", "7", "4"),
        (.sgd, .kwd, "0.2271", "10", "2.271"),
        (.sgd, .kwd, "0.22715", "1", "0.227"),
        (.kwd, .sgd, "4.4033", "1.5", "6.6"),
        (.sgd, .usd, "0.7412", "100", "74.12"),
    ])
    func convertsAndRoundsToTarget(
        source: Currency, target: Currency, rate: String, amount: String, expected: String
    ) throws {
        let rateUnderTest = try FXRate(source: source, target: target, rate: decimal(rate))
        let result = try rateUnderTest.convert(Money(amount: decimal(amount), currency: source))
        #expect(result == Money(amount: try decimal(expected), currency: target))
    }

    @Test func keepsRateAtFullPrecision() throws {
        let rateUnderTest = try FXRate(source: .sgd, target: .usd, rate: decimal("0.741234567"))
        #expect(rateUnderTest.rate == (try decimal("0.741234567")))
    }

    @Test func convertRejectsWrongSourceCurrency() throws {
        let rateUnderTest = try FXRate(source: .sgd, target: .jpy, rate: decimal("110"))
        #expect(throws: MoneyError.currencyMismatch(expected: .sgd, actual: .usd)) {
            try rateUnderTest.convert(Money(amountMinor: 100, currency: .usd))
        }
    }
}

@Suite struct FXQuoteTests {
    let expiry = Date(timeIntervalSince1970: 1_800_000_000)

    func makeQuote(source: Money? = nil, target: Money? = nil, fee: Money? = nil) throws -> FXQuote {
        let rate = try FXRate(source: .sgd, target: .jpy, rate: decimal("110"))
        return try FXQuote(
            id: "q_1",
            sourceAmount: source ?? Money(amountMinor: 10_000, currency: .sgd),
            targetAmount: target ?? Money(amountMinor: 11_000, currency: .jpy),
            rate: rate,
            fee: fee ?? Money(amountMinor: 150, currency: .sgd),
            expiresAt: expiry
        )
    }

    @Test func expiryIsInclusiveAtTheExactInstant() throws {
        let quote = try makeQuote()
        #expect(!quote.isExpired(at: expiry.addingTimeInterval(-0.001)))
        #expect(quote.isExpired(at: expiry))
        #expect(quote.isExpired(at: expiry.addingTimeInterval(0.001)))
    }

    @Test func rejectsSourceAmountInWrongCurrency() {
        #expect(throws: MoneyError.currencyMismatch(expected: .sgd, actual: .usd)) {
            try makeQuote(source: Money(amountMinor: 100, currency: .usd))
        }
    }

    @Test func rejectsTargetAmountInWrongCurrency() {
        #expect(throws: MoneyError.currencyMismatch(expected: .jpy, actual: .kwd)) {
            try makeQuote(target: Money(amountMinor: 100, currency: .kwd))
        }
    }

    @Test func rejectsFeeOutsideSourceCurrency() {
        // The fee is deducted from the source amount before conversion, so it must be in
        // the source currency. A target-currency fee would be a different pricing model.
        #expect(throws: MoneyError.currencyMismatch(expected: .sgd, actual: .jpy)) {
            try makeQuote(fee: Money(amountMinor: 150, currency: .jpy))
        }
    }
}

/// The app's own check of the server's quote (Phase 3 carry-over).
@Suite struct FXQuoteAddsUpTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func quote(source: Int64 = 10_000, target: Int64, fee: Int64 = 150, expiresIn: TimeInterval = 30) throws -> FXQuote
    {
        try FXQuote(
            id: "q",
            sourceAmount: Money(amountMinor: source, currency: .sgd),
            targetAmount: Money(amountMinor: target, currency: .usd),
            rate: try FXRate(source: .sgd, target: .usd, rate: try decimal("0.7412")),
            fee: Money(amountMinor: fee, currency: .sgd),
            expiresAt: now.addingTimeInterval(expiresIn)
        )
    }

    /// (100.00 - 1.50) x 0.7412 = 73.0082, so 73.01; one minor unit either way is rounding.
    @Test(arguments: [7_301, 7_300, 7_302])
    func correctMathsAddsUp(target: Int64) throws {
        #expect(try quote(target: target).addsUp(at: now))
    }

    @Test func wrongTargetDoesNotAddUp() throws {
        #expect(try !quote(target: 7_400).addsUp(at: now))
    }

    @Test(arguments: [Int64(10_000), 20_000, -1])
    func impossibleFeeDoesNotAddUp(fee: Int64) throws {
        #expect(try !quote(target: 0, fee: fee).addsUp(at: now))
    }

    @Test func expiredQuoteDoesNotAddUp() throws {
        #expect(try !quote(target: 7_301, expiresIn: 0).addsUp(at: now))
    }
}

@Suite struct TransferFailureCodeTests {
    /// Refusals of the Face ID approval, so the status screen can say what happened.
    @Test func approvalRefusalsHaveTheirOwnReasons() {
        #expect(TransferFailure(serverCode: "nonce_expired") == .approvalExpired)
        for code in ["invalid_signature", "payload_mismatch", "nonce_used", "invalid_nonce", "assertion_invalid"] {
            #expect(TransferFailure(serverCode: code) == .notApproved)
        }
    }
}
