import Domain
import Foundation

/// Every user-visible string in the feature, read from `Resources/en.lproj/Localizable.strings`.
/// English only (SPEC section 2). Code uses these properties, never the keys.
enum TransferStrings {
    static var recipientsTitle: String {
        text("transfer.recipients.title")
    }
    static var amountTitle: String {
        text("transfer.amount.title")
    }
    static var reviewTitle: String {
        text("transfer.review.title")
    }
    static var cancel: String {
        text("transfer.cancel")
    }
    static var retry: String {
        text("transfer.retry")
    }
    static var done: String {
        text("transfer.done")
    }
    static var noRecipients: String {
        text("transfer.recipients.empty")
    }
    static var youSend: String {
        text("transfer.amount.youSend")
    }
    static var tooMuch: String {
        text("transfer.amount.tooMuch")
    }
    static var continueTitle: String {
        text("transfer.amount.continue")
    }
    static var reviewYouSend: String {
        text("transfer.review.youSend")
    }
    static var fee: String {
        text("transfer.review.fee")
    }
    static var rate: String {
        text("transfer.review.rate")
    }
    static var requoting: String {
        text("transfer.review.requoting")
    }
    static var rateUpdatedTitle: String {
        text("transfer.review.rateUpdated.title")
    }
    static var rateUpdatedMessage: String {
        text("transfer.review.rateUpdated.message")
    }
    static var rateUpdatedOK: String {
        text("transfer.review.rateUpdated.ok")
    }
    static var send: String {
        text("transfer.review.send")
    }
    static var sendingTitle: String {
        text("transfer.status.sending.title")
    }
    static var sendingMessage: String {
        text("transfer.status.sending.message")
    }
    static var processingTitle: String {
        text("transfer.status.processing.title")
    }
    static var completedTitle: String {
        text("transfer.status.completed.title")
    }
    static var offlineTitle: String {
        text("transfer.error.offline.title")
    }
    static var offlineMessage: String {
        text("transfer.error.offline.message")
    }
    static var unavailableTitle: String {
        text("transfer.error.unavailable.title")
    }
    static var unavailableMessage: String {
        text("transfer.error.unavailable.message")
    }
    static var sessionExpiredTitle: String {
        text("transfer.error.sessionExpired.title")
    }
    static var sessionExpiredMessage: String {
        text("transfer.error.sessionExpired.message")
    }
    static var amountNotAllowedTitle: String {
        text("transfer.error.amountNotAllowed.title")
    }
    static var amountNotAllowedMessage: String {
        text("transfer.error.amountNotAllowed.message")
    }
    static var failedTitle: String {
        text("transfer.error.failed.title")
    }
    static var failedMessage: String {
        text("transfer.error.failed.message")
    }
    static var storageTitle: String {
        text("transfer.error.storage.title")
    }
    static var storageMessage: String {
        text("transfer.error.storage.message")
    }
    static func recipientSubtitle(currency: Currency, last4: String) -> String {
        String(format: text("transfer.recipients.subtitle"), currency.code, last4)
    }
    static func available(_ balance: String) -> String {
        String(format: text("transfer.amount.available"), balance)
    }
    /// "1 SGD = 0.7456 USD". The rate keeps all its digits: it is what the user agrees to.
    static func rate(_ rate: FXRate) -> String {
        String(format: text("transfer.review.rateValue"), rate.source.code, "\(rate.rate)", rate.target.code)
    }
    static func theyReceive(_ name: String) -> String {
        String(format: text("transfer.review.theyReceive"), name)
    }
    static func countdown(seconds: Int) -> String {
        seconds == 1
            ? text("transfer.review.countdown.one") : String(format: text("transfer.review.countdown.other"), seconds)
    }
    static func processingMessage(_ name: String) -> String {
        String(format: text("transfer.status.processing.message"), name)
    }
    static func completedMessage(_ name: String) -> String {
        String(format: text("transfer.status.completed.message"), name)
    }
    static func failedTitle(_ failure: TransferFailure) -> String {
        text("transfer.status.failed.\(failureKey(failure)).title")
    }
    static func failedMessage(_ failure: TransferFailure) -> String {
        text("transfer.status.failed.\(failureKey(failure)).message")
    }

    /// A used quote reads like an expired one: either way the user needs a new rate.
    private static func failureKey(_ failure: TransferFailure) -> String {
        switch failure {
        case .quoteExpired, .quoteUsed: "quoteExpired"
        case .insufficientFunds: "insufficientFunds"
        case .declined: "declined"
        case .rejected: "rejected"
        }
    }

    /// A missing key comes back as the key itself; `TransferStringsTests` catches that.
    private static func text(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    }
}
