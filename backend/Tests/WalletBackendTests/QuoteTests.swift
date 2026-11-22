import XCTVapor

@testable import WalletBackend

/// Expected numbers were computed independently with Python's `decimal` module
/// (half-even rounding), not with the code under test.
final class QuoteTests: XCTestCase {
    func testFeeIsDeductedInSourceCurrencyBeforeConversion() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()

            let quote = try await harness.quote(token: tokens.accessToken, minor: 10_000, from: "SGD", to: "USD")

            XCTAssertEqual(quote.sourceAmount, MoneyDTO(amountMinor: 10_000, currency: "SGD"))
            XCTAssertEqual(quote.fee, MoneyDTO(amountMinor: 100, currency: "SGD"))
            XCTAssertEqual(quote.rate, "0.74560095")
            // (100.00 - 1.00) * 0.74560095 = 73.814494... -> 73.81 USD
            XCTAssertEqual(quote.targetAmount, MoneyDTO(amountMinor: 7_381, currency: "USD"))
        }
    }

    func testConversionAcrossMinorUnitScales() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()
            let cases = [
                ExpectedQuote(10_000, "SGD", "JPY", fee: 100, target: 11_166),  // 2 -> 0 decimals
                ExpectedQuote(10_000, "JPY", "SGD", fee: 50, target: 8_822),  // 0 -> 2 decimals
                ExpectedQuote(1_250_000, "SGD", "EUR", fee: 6_250, target: 856_307),  // 0.5% fee above the minimum
                // 995.00 * 0.3071 = 305.5645 KWD: exactly half a fils, rounds to even.
                ExpectedQuote(100_000, "USD", "KWD", fee: 500, target: 305_564),
            ]
            for expected in cases {
                let quote = try await harness.quote(
                    token: tokens.accessToken,
                    minor: expected.sourceMinor,
                    from: expected.source,
                    to: expected.target
                )
                let label = "\(expected.source)->\(expected.target)"
                XCTAssertEqual(quote.fee.amountMinor, expected.feeMinor, label)
                XCTAssertEqual(quote.targetAmount.amountMinor, expected.targetMinor, label)
            }
        }
    }

    func testQuoteExpiresIn30Seconds() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()

            let quote = try await harness.quote(token: tokens.accessToken)

            XCTAssertEqual(quote.expiresAt, Harness.start.addingTimeInterval(30))
        }
    }

    func testRateIsAPlainDecimalString() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()

            let response = try await harness.send(
                .POST,
                "/v1/quotes",
                token: tokens.accessToken,
                json: QuoteRequest(sourceAmount: MoneyDTO(amountMinor: 100_000, currency: "USD"), targetCurrency: "KWD")
            )

            let body = try XCTUnwrap(response.body.string)
            XCTAssertTrue(body.contains(#""rate":"0.3071""#), body)
        }
    }

    func testInvalidQuoteRequestsAreRejected() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()
            let cases: [(MoneyDTO, String)] = [
                (MoneyDTO(amountMinor: 10_000, currency: "SGD"), "SGD"),  // same currency
                (MoneyDTO(amountMinor: 10_000, currency: "CHF"), "USD"),  // unsupported
                (MoneyDTO(amountMinor: 10_000, currency: "SGD"), "GBP"),  // unsupported
                (MoneyDTO(amountMinor: 0, currency: "SGD"), "USD"),
                (MoneyDTO(amountMinor: -500, currency: "SGD"), "USD"),
                (MoneyDTO(amountMinor: 100, currency: "SGD"), "USD"),  // not more than the fee
                (MoneyDTO(amountMinor: Int64.max, currency: "SGD"), "USD"),
            ]
            for (source, target) in cases {
                let response = try await harness.send(
                    .POST,
                    "/v1/quotes",
                    token: tokens.accessToken,
                    json: QuoteRequest(sourceAmount: source, targetCurrency: target)
                )
                XCTAssertEqual(response.status, .unprocessableEntity, "\(source) -> \(target)")
                XCTAssertEqual(response.envelope?.code, "invalid_request", "\(source) -> \(target)")
            }
        }
    }

    func testFractionalAmountIsRejected() async throws {
        try await withApp { harness in
            let tokens = try await harness.login()
            let body = #"{"sourceAmount":{"amountMinor":100.5,"currency":"SGD"},"targetCurrency":"USD"}"#

            let response = try await harness.app.testable().performTest(
                request: XCTHTTPRequest(
                    method: .POST,
                    url: URI(path: "/v1/quotes"),
                    headers: [
                        "Authorization": "Bearer \(tokens.accessToken)",
                        "Content-Type": "application/json",
                    ],
                    body: ByteBuffer(string: body)
                )
            )

            XCTAssertEqual(response.status, .badRequest)
            XCTAssertEqual(response.envelope?.code, "bad_request")
        }
    }

    func testFeeRule() {
        XCTAssertEqual(MoneyMath.fee(sourceMinor: 10_000, currency: "SGD"), 100)  // minimum 1.00
        XCTAssertEqual(MoneyMath.fee(sourceMinor: 20_001, currency: "SGD"), 101)  // 0.5% rounded up
        XCTAssertEqual(MoneyMath.fee(sourceMinor: 100, currency: "JPY"), 1)  // minimum 1 yen
        XCTAssertEqual(MoneyMath.fee(sourceMinor: 10_001, currency: "JPY"), 51)
        XCTAssertEqual(MoneyMath.fee(sourceMinor: 1_000_000, currency: "KWD"), 5_000)
    }
}

struct ExpectedQuote {
    let sourceMinor: Int64
    let source: String
    let target: String
    let feeMinor: Int64
    let targetMinor: Int64

    init(_ sourceMinor: Int64, _ source: String, _ target: String, fee: Int64, target targetMinor: Int64) {
        self.sourceMinor = sourceMinor
        self.source = source
        self.target = target
        self.feeMinor = fee
        self.targetMinor = targetMinor
    }
}
