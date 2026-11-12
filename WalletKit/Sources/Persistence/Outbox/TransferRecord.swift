import Domain
import Foundation
import SwiftData

/// One outbox row. Flat columns rather than nested `Codable` values, so a later change to a
/// Domain type can't silently change what is stored. Holds what the status screen and the
/// server calls need: amounts, rate, the recipient's name and last four digits. No tokens,
/// no full account numbers.
@Model
final class TransferRecord {
    @Attribute(.unique) var id: UUID
    var state: String
    var failure: String?
    var quoteID: String
    var sourceMinor: Int64
    var sourceCurrency: String
    var targetMinor: Int64
    var targetCurrency: String
    var feeMinor: Int64
    /// The decimal rate as text, so it never passes through `Double`.
    var rate: String
    var quoteExpiresAt: Date
    var recipientID: String
    var recipientName: String
    var recipientLast4: String
    var sourceAccountID: String
    var createdAt: Date
    var updatedAt: Date

    init(_ transfer: Transfer) throws(MoneyError) {
        let draft = transfer.draft
        let quote = draft.quote
        id = draft.id
        state = transfer.state.rawValue
        failure = transfer.failure?.rawValue
        quoteID = quote.id
        sourceMinor = try quote.sourceAmount.amountMinor()
        sourceCurrency = quote.sourceAmount.currency.code
        targetMinor = try quote.targetAmount.amountMinor()
        targetCurrency = quote.targetAmount.currency.code
        feeMinor = try quote.fee.amountMinor()
        rate = quote.rate.rate.description
        quoteExpiresAt = quote.expiresAt
        recipientID = draft.recipient.id
        recipientName = draft.recipient.name
        recipientLast4 = draft.recipient.accountLast4
        sourceAccountID = draft.sourceAccountID
        createdAt = transfer.createdAt
        updatedAt = transfer.updatedAt
    }

    func update(from transfer: Transfer) {
        state = transfer.state.rawValue
        failure = transfer.failure?.rawValue
        updatedAt = transfer.updatedAt
    }

    /// `nil` when the row can't be read back (an unknown currency or state).
    func transfer() -> Transfer? {
        guard let source = Currency.supported(code: sourceCurrency),
            let target = Currency.supported(code: targetCurrency),
            let state = TransferState(rawValue: state),
            let rateValue = Decimal(string: rate, locale: Locale(identifier: "en_US_POSIX")),
            let fxRate = try? FXRate(source: source, target: target, rate: rateValue),
            let quote = try? FXQuote(
                id: quoteID,
                sourceAmount: Money(amountMinor: sourceMinor, currency: source),
                targetAmount: Money(amountMinor: targetMinor, currency: target),
                rate: fxRate,
                fee: Money(amountMinor: feeMinor, currency: source),
                expiresAt: quoteExpiresAt
            )
        else {
            return nil
        }
        let recipient = Recipient(id: recipientID, name: recipientName, currency: target, accountLast4: recipientLast4)
        let draft = TransferDraft(id: id, quote: quote, recipient: recipient, sourceAccountID: sourceAccountID)
        return Transfer(
            draft: draft,
            state: state,
            failure: failure.flatMap(TransferFailure.init(rawValue:)),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
