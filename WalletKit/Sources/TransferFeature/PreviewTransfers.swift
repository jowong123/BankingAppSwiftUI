#if DEBUG
    import Domain
    import Foundation

    /// Sample data and instant fakes for SwiftUI previews. Not compiled into release builds.
    enum PreviewTransfers {
        static let account = Account(
            id: "acc_sgd", balance: Money(amountMinor: 1_250_000, currency: .sgd), updatedAt: .now)
        static let recipient = Recipient(id: "rcp_alice_usd", name: "Alice Tan", currency: .usd, accountLast4: "4821")
        static let sentID = UUID()

        static var dependencies: TransferDependencies {
            TransferDependencies(repository: Repository(), outbox: Outbox())
        }

        static func quote() -> FXQuote {
            // Fixed sample values that always satisfy FXQuote's currency checks.
            let rate = (try? FXRate(source: .sgd, target: .usd, rate: Decimal(string: "0.7341") ?? 1))
            return rate.flatMap {
                try? FXQuote(
                    id: "q_preview",
                    sourceAmount: Money(amountMinor: 10_000, currency: .sgd),
                    targetAmount: Money(amountMinor: 7_230, currency: .usd),
                    rate: $0,
                    fee: Money(amountMinor: 150, currency: .sgd),
                    expiresAt: .now.addingTimeInterval(30)
                )
            } ?? fallbackQuote
        }

        private static var fallbackQuote: FXQuote {
            preconditionFailure("preview quote")
        }

        private struct Repository: TransfersRepository {
            func recipients() async throws(TransferError) -> [Recipient] {
                [PreviewTransfers.recipient]
            }
            func quote(sourceAmount: Money, targetCurrency: Currency) async throws(TransferError) -> FXQuote {
                PreviewTransfers.quote()
            }
        }

        private struct Outbox: TransferOutboxing {
            func send(_ draft: TransferDraft) async throws(TransferError) -> Transfer {
                Transfer(draft: draft, state: .authorised, createdAt: .now, updatedAt: .now)
            }
            func updates(for id: UUID) async -> AsyncStream<Transfer> {
                let draft = TransferDraft(
                    id: id, quote: PreviewTransfers.quote(), recipient: PreviewTransfers.recipient,
                    sourceAccountID: "acc_sgd")
                return AsyncStream {
                    $0.yield(Transfer(draft: draft, state: .processing, createdAt: .now, updatedAt: .now))
                }
            }
            func resumePending() async {}
            func hasPending() async -> Bool {
                false
            }
            func removeAll() async {}
        }
    }
#endif
