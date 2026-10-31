import Domain
import Foundation
import Testing

@testable import Networking

@Suite struct MoneyDTOTests {
    @Test(arguments: [
        (Currency.jpy, Int64(1_250), "1250"),
        (.sgd, 125_000, "1250"),
        (.sgd, -199, "-1.99"),
        (.kwd, 1_234, "1.234"),
        (.kwd, 1, "0.001"),
        (.usd, 0, "0"),
    ])
    func roundTripsThroughMinorUnits(currency: Currency, minor: Int64, amount: String) throws {
        let expected = Money(amount: try #require(Decimal(string: amount)), currency: currency)

        let decoded = try MoneyDTO(amountMinor: minor, currency: currency.code).money()
        let encoded = try MoneyDTO(expected)

        #expect(decoded == expected)
        #expect(encoded == MoneyDTO(amountMinor: minor, currency: currency.code))
    }

    @Test(arguments: [Int64.max, Int64.min, 0])
    func extremeMinorAmountsRoundTripExactly(minor: Int64) throws {
        let money = try MoneyDTO(amountMinor: minor, currency: "SGD").money()

        #expect(try MoneyDTO(money).amountMinor == minor)
    }

    @Test func decodesFromTheWireShape() throws {
        let data = Data(#"{"amountMinor":125000,"currency":"SGD"}"#.utf8)

        let dto = try WalletJSON.decoder().decode(MoneyDTO.self, from: data)

        #expect(try dto.money() == Money(amountMinor: 125_000, currency: .sgd))
    }

    @Test func floatAmountIsRejected() {
        // The contract is integer minor units; 1250.5 must not be silently truncated.
        let data = Data(#"{"amountMinor":1250.5,"currency":"SGD"}"#.utf8)

        #expect(throws: DecodingError.self) {
            try WalletJSON.decoder().decode(MoneyDTO.self, from: data)
        }
    }

    @Test(arguments: ["CHF", "sgd", "XXX"])
    func unsupportedCurrencyIsRejectedNotGuessed(code: String) {
        #expect(throws: APIError.invalidResponse("unsupported currency")) {
            try MoneyDTO(amountMinor: 100, currency: code).money()
        }
    }
}

@Suite struct QuoteDTOTests {
    func quoteJSON(fee: String = #"{"amountMinor":150,"currency":"SGD"}"#, rate: String = "0.741234567") -> Data {
        Data(
            """
            {"id":"q_1",
             "sourceAmount":{"amountMinor":10000,"currency":"SGD"},
             "targetAmount":{"amountMinor":7301,"currency":"USD"},
             "fee":\(fee),
             "rate":"\(rate)",
             "expiresAt":"2026-10-26T10:00:30Z"}
            """.utf8
        )
    }

    @Test func mapsToDomainQuoteWithExactRate() throws {
        let quote = try WalletJSON.decoder().decode(QuoteDTO.self, from: quoteJSON()).quote()

        #expect(quote.id == "q_1")
        #expect(quote.sourceAmount == Money(amountMinor: 10_000, currency: .sgd))
        #expect(quote.targetAmount == Money(amountMinor: 7_301, currency: .usd))
        #expect(quote.fee == Money(amountMinor: 150, currency: .sgd))
        #expect(quote.rate.rate == Decimal(string: "0.741234567"))
        #expect(quote.expiresAt == Date(timeIntervalSince1970: 1_793_008_830))
    }

    @Test func feeInTargetCurrencyIsRejected() throws {
        let dto = try WalletJSON.decoder().decode(
            QuoteDTO.self,
            from: quoteJSON(fee: #"{"amountMinor":150,"currency":"USD"}"#)
        )

        #expect(throws: APIError.invalidResponse("quote")) { try dto.quote() }
    }

    @Test(arguments: ["abc", "", "0", "-1.2", "1,5", "1.2abc", "1e3", " 1.5", ".5"])
    func invalidRateIsRejected(rate: String) throws {
        let dto = try WalletJSON.decoder().decode(QuoteDTO.self, from: quoteJSON(rate: rate))

        #expect(throws: APIError.self) { try dto.quote() }
    }
}

@Suite struct OtherDTOTests {
    @Test func unknownTransferStatusDecodesAsUnknown() throws {
        let data = Data(#"["processing","on_hold"]"#.utf8)

        let statuses = try WalletJSON.decoder().decode([TransferDTO.Status].self, from: data)

        #expect(statuses == [.processing, .unknown])
    }

    @Test func sessionTokensAreRedactedWhenPrinted() throws {
        let data = Data(#"{"accessToken":"secret-a","refreshToken":"secret-r","expiresIn":900}"#.utf8)

        let tokens = try WalletJSON.decoder().decode(SessionTokensDTO.self, from: data)

        let dumped = reflected(tokens)
        #expect(!"\(tokens)".contains("secret"))
        #expect(!String(reflecting: tokens).contains("secret"))
        #expect(!dumped.contains("secret"))
        #expect(tokens.accessToken == "secret-a")
    }

    @Test func requestBodiesWithSecretsAreRedactedWhenPrinted() {
        let login = LoginRequestDTO(email: "demo@wallet.test", password: "hunter2")
        let refresh = RefreshRequestDTO(refreshToken: "secret-r")
        let dumped = reflected(login) + reflected(refresh)

        #expect(!dumped.contains("hunter2") && !dumped.contains("secret-r"))
        #expect(!"\(login) \(refresh)".contains("hunter2"))
        #expect(!"\(login) \(refresh)".contains("secret-r"))
    }
}

/// What `dump`, debuggers and test diffs see: every child of the value's mirror.
private func reflected(_ value: Any) -> String {
    Mirror(reflecting: value).children.map { "\($0.label ?? ""): \($0.value)" }.joined(separator: ", ")
}
