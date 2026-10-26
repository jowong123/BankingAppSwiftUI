import Testing

@testable import Domain

@Suite struct TransferStateMachineTests {
    /// The 9 arrows in the docs/SPEC.md section 5 diagram, written out independently of
    /// the implementation so a typo in either one fails the test.
    static let validTransitions: [TransferState: [TransferEvent: TransferState]] = [
        .draft: [.quoteReceived: .quoted],
        .quoted: [.quoteExpired: .expired, .authorised: .authorised],
        .expired: [.quoteReceived: .quoted],
        .authorised: [.confirmSent: .submitted],
        .submitted: [.serverAccepted: .processing, .rejected: .failed],
        .processing: [.settled: .completed, .declined: .failed],
    ]

    @Test func tableHasNineTransitions() {
        #expect(Self.validTransitions.values.map(\.count).reduce(0, +) == 9)
    }

    /// Every one of the 8 × 8 = 64 (state, event) pairs: valid ones move to the
    /// expected state, all others throw and name the pair.
    @Test(arguments: TransferState.allCases, TransferEvent.allCases)
    func everyPair(state: TransferState, event: TransferEvent) throws {
        if let expected = Self.validTransitions[state]?[event] {
            #expect(try TransferStateMachine.next(state, event) == expected)
        } else {
            #expect(throws: TransferTransitionError.invalid(from: state, event: event)) {
                try TransferStateMachine.next(state, event)
            }
        }
    }

    @Test(arguments: TransferState.allCases)
    func terminalStatesAcceptNoEvents(state: TransferState) {
        let acceptsAnything = TransferEvent.allCases.contains { (try? TransferStateMachine.next(state, $0)) != nil }
        #expect(state.isTerminal == !acceptsAnything)
        #expect(state.isTerminal == [.completed, .failed].contains(state))
    }

    @Test func happyPathWithReQuote() throws {
        let events: [TransferEvent] = [
            .quoteReceived, .quoteExpired, .quoteReceived, .authorised, .confirmSent, .serverAccepted, .settled,
        ]
        var state = TransferState.draft
        for event in events {
            state = try TransferStateMachine.next(state, event)
        }
        #expect(state == .completed)
    }

    @Test func cannotAuthoriseAnExpiredQuote() {
        // The user must see the new rate first: Expired has to go back through Quoted.
        #expect(throws: TransferTransitionError.invalid(from: .expired, event: .authorised)) {
            try TransferStateMachine.next(.expired, .authorised)
        }
    }

    @Test func cannotFailBeforeSubmitting() {
        // Before the confirm request is sent, nothing has reached the server to reject.
        for state in [TransferState.draft, .quoted, .expired, .authorised] {
            for event in [TransferEvent.rejected, .declined] {
                #expect(throws: TransferTransitionError.self) { try TransferStateMachine.next(state, event) }
            }
        }
    }
}
