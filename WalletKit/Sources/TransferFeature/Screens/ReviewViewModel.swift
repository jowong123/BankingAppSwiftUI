import Domain
import Foundation
import Observation

/// The quote with its 30 s countdown, then Send.
///
/// - When the countdown ends, a new quote is fetched and shown with a "Rate updated" notice.
///   Send stays off until the user taps OK on it: a rate never changes silently (SPEC
///   section 5).
/// - The transfer ID is made once, when the screen opens. A double tap, or a tap while the
///   first send is still saving, can only ever send that one ID.
@Observable @MainActor
final class ReviewViewModel {
    struct State: Equatable {
        var quote: FXQuote
        var secondsLeft: Int
        var rateUpdated = false
        var isRequoting = false
        var isSending = false
        var error: UserFacingError?

        var canSend: Bool {
            secondsLeft > 0 && !rateUpdated && !isRequoting && !isSending
        }
    }

    private(set) var state: State
    let recipient: Recipient
    let transferID = UUID()
    private let source: Account
    private let dependencies: TransferDependencies
    private let router: TransferRouter
    private let onSessionExpired: @MainActor () -> Void

    init(
        source: Account,
        recipient: Recipient,
        quote: FXQuote,
        dependencies: TransferDependencies,
        router: TransferRouter,
        onSessionExpired: @escaping @MainActor () -> Void
    ) {
        self.source = source
        self.recipient = recipient
        self.dependencies = dependencies
        self.router = router
        self.onSessionExpired = onSessionExpired
        state = State(quote: quote, secondsLeft: Self.seconds(until: quote.expiresAt, from: dependencies.now()))
    }

    /// Runs while the screen is visible (`.task(id: quote.id)`), so a new quote restarts it.
    /// Ends after asking for a new quote; if that fails the error offers Retry.
    func runCountdown() async {
        while !Task.isCancelled {
            let remaining = state.quote.expiresAt.timeIntervalSince(dependencies.now())
            state.secondsLeft = Self.seconds(until: state.quote.expiresAt, from: dependencies.now())
            guard remaining > 0 else {
                // Sending already: the rate on screen must stay the one being sent.
                if !state.isSending {
                    await requote()
                }
                return
            }
            do {
                try await dependencies.sleep(.milliseconds(Int(min(remaining, 1) * 1000)))
            } catch {
                return
            }
        }
    }

    func acknowledgeNewRate() {
        state.rateUpdated = false
    }

    func retry() async {
        await requote()
    }

    func send() async {
        guard state.canSend else {
            return
        }
        // The countdown ticks once a second: check the time itself before sending.
        guard !state.quote.isExpired(at: dependencies.now()) else {
            await requote()
            return
        }
        state.isSending = true
        let draft = TransferDraft(
            id: transferID,
            quote: state.quote,
            recipient: recipient,
            sourceAccountID: source.id
        )
        do throws(TransferError) {
            _ = try await dependencies.outbox.send(draft)
            // `isSending` stays on: this screen is about to be replaced by the status.
            router.showStatus(of: transferID)
        } catch {
            state.isSending = false
            state.error = TransferMessages.userFacing(error)
        }
    }

    private func requote() async {
        guard !state.isRequoting, !state.isSending else {
            return
        }
        state.isRequoting = true
        defer {
            state.isRequoting = false
        }
        do throws(TransferError) {
            let quote = try await dependencies.repository.quote(
                sourceAmount: state.quote.sourceAmount,
                targetCurrency: recipient.currency
            )
            state.quote = quote
            state.secondsLeft = Self.seconds(until: quote.expiresAt, from: dependencies.now())
            state.rateUpdated = true
            state.error = nil
        } catch {
            if error == .sessionExpired {
                onSessionExpired()
            }
            if let shown = TransferMessages.userFacing(error) {
                state.error = shown
            }
        }
    }

    private static func seconds(until expiry: Date, from now: Date) -> Int {
        max(0, Int(expiry.timeIntervalSince(now).rounded(.up)))
    }
}
