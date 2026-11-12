#if DEBUG
    import Domain
    import Foundation

    /// The `-mockServer` stand-in for the backend: accounts, history, recipients, quotes and
    /// transfers in memory, with the backend seed's data, fee and rates (`backend/.../SeedData.swift`,
    /// `MoneyMath`, `RateTable`). A confirmed transfer debits the account and adds a history
    /// row, so UI tests see the same effects as against the real server. Debug only.
    actor MockBank {
        /// Units of each currency per 1 USD, as `RateTable.base` in the backend.
        static let perUSD: [String: Decimal] = [
            "USD": 1,
            "SGD": Decimal(string: "1.3412") ?? 1,
            "EUR": Decimal(string: "0.9234") ?? 1,
            "JPY": Decimal(string: "151.27") ?? 1,
            "KWD": Decimal(string: "0.3071") ?? 1,
        ]
        static let recipients = [
            Recipient(id: "rcp_alice_usd", name: "Alice Tan", currency: .usd, accountLast4: "4821"),
            Recipient(id: "rcp_kenji_jpy", name: "Kenji Sato", currency: .jpy, accountLast4: "0937"),
            Recipient(id: "rcp_marie_eur", name: "Marie Dubois", currency: .eur, accountLast4: "7710"),
            Recipient(id: "rcp_omar_kwd", name: "Omar Al-Sabah", currency: .kwd, accountLast4: "3302"),
        ]

        let accountOrder: [String]
        private(set) var accountsByID: [String: Account]
        private(set) var history: [String: [AccountTransaction]]
        private var transfers: [UUID: MockTransfer] = [:]
        private let quoteLifetime: TimeInterval
        private let settleDelay: TimeInterval

        /// - Parameter quoteLifetime: seconds a quote holds; UI tests shorten it (`-quoteSeconds`).
        init(now: Date = .now, quoteLifetime: TimeInterval = 30, settleDelay: TimeInterval = 1) {
            let accounts = [
                Account(id: "acc_sgd", balance: Money(amountMinor: 1_250_000, currency: .sgd), updatedAt: now),
                Account(id: "acc_usd", balance: Money(amountMinor: 320_000, currency: .usd), updatedAt: now),
                Account(id: "acc_jpy", balance: Money(amountMinor: 150_000, currency: .jpy), updatedAt: now),
                Account(id: "acc_kwd", balance: Money(amountMinor: 120_500, currency: .kwd), updatedAt: now),
            ]
            self.accountOrder = accounts.map(\.id)
            self.accountsByID = Dictionary(
                uniqueKeysWithValues: accounts.map {
                    ($0.id, $0)
                })
            self.history = Self.seedHistory(now: now)
            self.quoteLifetime = quoteLifetime
            self.settleDelay = settleDelay
        }

        func accounts() -> [Account] {
            accountOrder.compactMap {
                accountsByID[$0]
            }
        }

        func transactions(_ accountID: String) -> [AccountTransaction] {
            history[accountID] ?? []
        }

        /// Fee 0.5% rounded up (at least 1.00, or 1 for JPY), deducted before converting.
        func quote(sourceAmount: Money, targetCurrency: Currency) throws(TransferError) -> FXQuote {
            let source = sourceAmount.currency
            guard let sourceMinor = try? sourceAmount.amountMinor(), source != targetCurrency,
                let sourcePerUSD = Self.perUSD[source.code], let targetPerUSD = Self.perUSD[targetCurrency.code]
            else {
                throw .invalidData
            }
            let minimum: Int64 = source.minorUnits == 0 ? 1 : 100
            let fee = max(minimum, (sourceMinor * 50 + 9_999) / 10_000)
            guard sourceMinor > fee else {
                throw .amountNotAllowed
            }
            let rate = Self.rounded(targetPerUSD / sourcePerUSD, scale: 8)
            let net = Money(amountMinor: sourceMinor - fee, currency: source).amount
            let target = Money(
                amount: Self.rounded(net * rate, scale: targetCurrency.minorUnits), currency: targetCurrency)
            do {
                return try FXQuote(
                    id: "q_\(UUID().uuidString.lowercased())",
                    sourceAmount: sourceAmount,
                    targetAmount: target,
                    rate: try FXRate(source: source, target: targetCurrency, rate: rate),
                    fee: Money(amountMinor: fee, currency: source),
                    expiresAt: Date().addingTimeInterval(quoteLifetime)
                )
            } catch {
                throw .invalidData
            }
        }

        func create(_ draft: TransferDraft) -> RemoteTransferStatus {
            if let existing = transfers[draft.id] {
                return existing.status
            }
            transfers[draft.id] = MockTransfer(draft: draft, status: .awaitingConfirmation, confirmedAt: nil)
            return .awaitingConfirmation
        }

        /// Debits once. A transfer this bank never saw (the app was relaunched, which resets the
        /// mock) is treated as already confirmed, as the real server would have it.
        func confirm(_ id: UUID) -> RemoteTransferStatus {
            guard var transfer = transfers[id] else {
                return .processing
            }
            guard transfer.status == .awaitingConfirmation else {
                return transfer.status
            }
            let quote = transfer.draft.quote
            guard let account = accountsByID[transfer.draft.sourceAccountID],
                let debited = try? account.balance.subtracting(quote.sourceAmount), !debited.isNegative
            else {
                transfer.status = .failed(.insufficientFunds)
                transfers[id] = transfer
                return transfer.status
            }
            accountsByID[account.id] = Account(id: account.id, balance: debited, updatedAt: Date())
            history[account.id, default: []].insert(
                AccountTransaction(
                    id: "txn_\(id.uuidString.lowercased())",
                    accountID: account.id,
                    amount: quote.sourceAmount.negated(),
                    description: "To \(transfer.draft.recipient.name)",
                    createdAt: Date()
                ),
                at: 0
            )
            transfer.status = .processing
            transfer.confirmedAt = Date()
            transfers[id] = transfer
            return .processing
        }

        /// Settles `settleDelay` after the confirm. Unknown transfers are long settled.
        func status(_ id: UUID) -> RemoteTransferStatus {
            guard var transfer = transfers[id] else {
                return .completed
            }
            if transfer.status == .processing, let confirmed = transfer.confirmedAt,
                Date().timeIntervalSince(confirmed) >= settleDelay
            {
                transfer.status = .completed
                transfers[id] = transfer
            }
            return transfer.status
        }

        private static func rounded(_ value: Decimal, scale: Int) -> Decimal {
            var input = value
            var result = Decimal()
            NSDecimalRound(&result, &input, scale, .bankers)
            return result
        }

        /// Newest first, one hour apart, matching the backend seed's amounts and merchants.
        private static func seedHistory(now: Date) -> [String: [AccountTransaction]] {
            let merchants = ["Kopi Corner", "MRT Top-up", "FairPrice", "Grab", "Salary", "Netflix", "Uniqlo", "Refund"]
            var sgd: [AccountTransaction] = []
            for index in (0..<45).reversed() {
                let merchant = merchants[index % merchants.count]
                let incoming = merchant == "Salary" || merchant == "Refund"
                let amount = Int64(350 + (index * 137) % 9_000)
                sgd.append(
                    AccountTransaction(
                        id: "txn_sgd_\(index)",
                        accountID: "acc_sgd",
                        amount: Money(amountMinor: incoming ? amount * 10 : -amount, currency: .sgd),
                        description: merchant,
                        createdAt: now.addingTimeInterval(TimeInterval(-(45 - index) * 3_600))
                    )
                )
            }
            func history(_ accountID: String, _ currency: Currency, _ items: [SeedEntry]) -> [AccountTransaction] {
                items.map { item in
                    AccountTransaction(
                        id: item.id,
                        accountID: accountID,
                        amount: Money(amountMinor: item.minor, currency: currency),
                        description: item.text,
                        createdAt: now.addingTimeInterval(TimeInterval(-item.hoursAgo * 3_600))
                    )
                }
            }
            return [
                "acc_sgd": sgd,
                "acc_usd": history(
                    "acc_usd", .usd,
                    [
                        SeedEntry(id: "txn_usd_2", minor: 120_000, text: "Transfer in", hoursAgo: 2),
                        SeedEntry(id: "txn_usd_1", minor: -4_599, text: "Amazon", hoursAgo: 5),
                    ]),
                "acc_jpy": history(
                    "acc_jpy", .jpy,
                    [
                        SeedEntry(id: "txn_jpy_2", minor: 50_000, text: "Transfer in", hoursAgo: 3),
                        SeedEntry(id: "txn_jpy_1", minor: -1_200, text: "Lawson", hoursAgo: 6),
                    ]),
                "acc_kwd": history(
                    "acc_kwd", .kwd, [SeedEntry(id: "txn_kwd_1", minor: -2_750, text: "Talabat", hoursAgo: 4)]),
            ]
        }
    }

    private struct MockTransfer {
        let draft: TransferDraft
        var status: RemoteTransferStatus
        var confirmedAt: Date?
    }

    /// One seeded non-SGD transaction, newest first per account.
    private struct SeedEntry {
        let id: String
        let minor: Int64
        let text: String
        let hoursAgo: Int
    }
#endif
