import Testing

@testable import Domain

@Suite struct TransferRecoveryTests {
    @Test(arguments: [
        (TransferState.authorised, TransferRecovery.Step.create),
        (.submitted, .confirm),
        (.processing, .poll),
        (.completed, .done),
        (.failed, .done),
        (.draft, .done),
        (.quoted, .done),
        (.expired, .done),
    ])
    func eachUnfinishedStateHasOneNextStep(state: TransferState, step: TransferRecovery.Step) {
        #expect(TransferRecovery.step(for: state) == step)
    }

    /// Whatever the server reports, the events are valid from the app's state and land on
    /// the matching state. After a crash the server can be several steps ahead.
    @Test(arguments: [
        (TransferState.authorised, RemoteTransferStatus.awaitingConfirmation, TransferState.submitted),
        (.authorised, .processing, .processing),
        (.authorised, .completed, .completed),
        (.authorised, .failed(.insufficientFunds), .failed),
        (.submitted, .processing, .processing),
        (.submitted, .completed, .completed),
        (.submitted, .failed(.declined), .failed),
        (.processing, .completed, .completed),
        (.processing, .failed(.declined), .failed),
    ])
    func eventsCatchUpWithTheServer(
        from state: TransferState,
        remote: RemoteTransferStatus,
        expected: TransferState
    ) throws {
        var current = state
        for event in TransferRecovery.events(from: state, to: remote) {
            current = try TransferStateMachine.next(current, event)
        }
        #expect(current == expected)
    }

    /// Nothing moves backwards or sideways: a status the app is already past, or one it
    /// doesn't know, changes nothing and the outbox asks again later.
    @Test(arguments: [
        (TransferState.submitted, RemoteTransferStatus.awaitingConfirmation),
        (.processing, .awaitingConfirmation),
        (.processing, .processing),
        (.authorised, .unknown),
        (.processing, .unknown),
        (.completed, .failed(.declined)),
        (.failed, .completed),
    ])
    func staleOrUnknownStatusChangesNothing(state: TransferState, remote: RemoteTransferStatus) {
        #expect(TransferRecovery.events(from: state, to: remote).isEmpty)
    }

    @Test func aRefusalBeforeConfirmFailsTheTransfer() throws {
        let event = try #require(TransferRecovery.refusalEvent(at: .authorised))
        #expect(try TransferStateMachine.next(.authorised, event) == .failed)
        #expect(TransferRecovery.refusalEvent(at: .processing) == nil)
    }

    @Test(arguments: [
        ("quote_expired", TransferFailure.quoteExpired),
        ("quote_used", .quoteUsed),
        ("insufficient_funds", .insufficientFunds),
        ("declined", .declined),
        ("something_new", .rejected),
    ])
    func serverReasonCodesMapToFailures(code: String, failure: TransferFailure) {
        #expect(TransferFailure(serverCode: code) == failure)
        #expect(TransferFailure(serverCode: nil) == .rejected)
    }
}
