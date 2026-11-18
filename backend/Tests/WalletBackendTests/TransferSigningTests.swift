import Crypto
import SQLKit
import XCTVapor

@testable import WalletBackend

/// The Phase 7 "done when": a confirm moves money only with a valid signature over exactly
/// this transfer and a fresh, unused nonce. Each refusal leaves the transfer unconfirmed and
/// the balance untouched.
final class TransferSigningTests: XCTestCase {
    func testUnsignedConfirmIsRefused() async throws {
        try await withApp { harness in
            let session = try await harness.login()
            let transfer = try await created(harness, session)

            let response = try await harness.send(
                .POST, "/v1/transfers/\(transfer.id)/confirm", token: session.accessToken)

            XCTAssertEqual(response.envelope?.code, "signature_required")
            try await assertNothingMoved(harness, session, transfer)
        }
    }

    /// The user approved 100.00; the request says 1.00. The signature covers the approved
    /// amount, so changing it breaks the signature, and signing the change needs the key.
    func testTamperedAmountIsRefused() async throws {
        try await withApp { harness in
            let session = try await harness.login()
            let transfer = try await created(harness, session)
            let nonce = try await challenge(harness, session, transfer.id)
            let signed = harness.payload(for: transfer, nonce: nonce)
            let tampered = ConfirmPayload(
                transferId: signed.transferId,
                amountMinor: signed.amountMinor - 9_900,
                currency: signed.currency,
                recipientId: signed.recipientId,
                quoteId: signed.quoteId,
                nonce: signed.nonce,
                timestamp: signed.timestamp
            )

            // Signed for the real amount, sent with the changed one.
            let swapped = try await sendSwapped(harness, session, transfer.id, signed: signed, sent: tampered)
            // Signed with the device key, but for an amount the transfer doesn't have.
            let mismatched = try await harness.sendConfirm(session, id: transfer.id, payload: tampered)

            XCTAssertEqual(swapped.envelope?.code, "invalid_signature")
            XCTAssertEqual(mismatched.envelope?.code, "payload_mismatch")
            try await assertNothingMoved(harness, session, transfer)
        }
    }

    func testExpiredNonceIsRefused() async throws {
        try await withApp { harness in
            let session = try await harness.login()
            let transfer = try await created(harness, session)
            let nonce = try await challenge(harness, session, transfer.id)

            harness.advance(61)
            let response = try await harness.sendConfirm(
                session, id: transfer.id, payload: harness.payload(for: transfer, nonce: nonce))

            XCTAssertEqual(response.envelope?.code, "nonce_expired")
            try await assertNothingMoved(harness, session, transfer)
        }
    }

    /// A captured confirm replayed: on its own transfer it only returns the status (money
    /// moved once); its nonce on another transfer is refused; a nonce already used is refused.
    func testReusedNonceIsRefused() async throws {
        try await withApp { harness in
            let session = try await harness.login()
            let first = try await created(harness, session)
            let second = try await created(harness, session)
            let nonce = try await challenge(harness, session, first.id)
            let payload = harness.payload(for: first, nonce: nonce)
            _ = try await harness.sendConfirm(session, id: first.id, payload: payload)

            let replayed = try await harness.sendConfirm(session, id: first.id, payload: payload)
            let onAnother = try await harness.sendConfirm(
                session, id: second.id, payload: harness.payload(for: second, nonce: nonce))
            let usedNonce = try await challenge(harness, session, second.id)
            try await harness.app.db.sqlDatabase().update("challenges")
                .set("usedAt", to: 1).where("nonce", .equal, usedNonce).run()
            let used = try await harness.sendConfirm(
                session, id: second.id, payload: harness.payload(for: second, nonce: usedNonce))

            XCTAssertEqual(try replayed.content.decode(TransferDTO.self).status, "processing")
            XCTAssertEqual(onAnother.envelope?.code, "invalid_nonce")
            XCTAssertEqual(used.envelope?.code, "nonce_used")
            let balance = try await TransferConfirmTests().balanceMinor(harness, "acc_sgd")
            XCTAssertEqual(balance, 1_250_000 - 10_000)
        }
    }

    /// Another device of the same user can't approve with its own key using this nonce.
    func testOtherDevicesKeyIsRefused() async throws {
        try await withApp { harness in
            let session = try await harness.login()
            let transfer = try await created(harness, session)
            let nonce = try await challenge(harness, session, transfer.id)

            let response = try await harness.sendConfirm(
                session,
                id: transfer.id,
                payload: harness.payload(for: transfer, nonce: nonce),
                key: P256.Signing.PrivateKey()
            )

            XCTAssertEqual(response.envelope?.code, "invalid_signature")
            try await assertNothingMoved(harness, session, transfer)
        }
    }

    /// A nonce is issued to one device; a second device of the same user can't use it.
    func testNonceFromAnotherDeviceIsRefused() async throws {
        try await withApp { harness in
            let phone = try await harness.login()
            let tablet = try await harness.login()
            let transfer = try await created(harness, phone)
            let nonce = try await challenge(harness, phone, transfer.id)

            let response = try await harness.sendConfirm(
                tablet, id: transfer.id, payload: harness.payload(for: transfer, nonce: nonce))

            XCTAssertEqual(response.envelope?.code, "invalid_nonce")
            try await assertNothingMoved(harness, phone, transfer)
        }
    }

    func testChallengeForAnotherUsersTransferIsNotFound() async throws {
        try await withApp { harness in
            let demo = try await harness.login()
            let transfer = try await created(harness, demo)
            let other = try await harness.login(email: Sandbox.otherEmail, password: Sandbox.otherPassword)

            let response = try await harness.send(
                .POST, "/v1/transfers/\(transfer.id)/challenge", token: other.accessToken)

            XCTAssertEqual(response.status, .notFound)
        }
    }

    /// Every signed field must match the stored transfer, not only the amount.
    func testEveryTamperedFieldIsRefused() async throws {
        try await withApp { harness in
            let session = try await harness.login()
            let transfer = try await created(harness, session)
            let nonce = try await challenge(harness, session, transfer.id)
            let real = harness.payload(for: transfer, nonce: nonce)
            let tampered = [
                ConfirmPayload(
                    transferId: real.transferId, amountMinor: real.amountMinor, currency: "USD",
                    recipientId: real.recipientId, quoteId: real.quoteId, nonce: nonce, timestamp: real.timestamp),
                ConfirmPayload(
                    transferId: real.transferId, amountMinor: real.amountMinor, currency: real.currency,
                    recipientId: "rcp_bob_eur", quoteId: real.quoteId, nonce: nonce, timestamp: real.timestamp),
                ConfirmPayload(
                    transferId: real.transferId, amountMinor: real.amountMinor, currency: real.currency,
                    recipientId: real.recipientId, quoteId: "q_other", nonce: nonce, timestamp: real.timestamp),
                ConfirmPayload(
                    transferId: UUID().uuidString.lowercased(), amountMinor: real.amountMinor,
                    currency: real.currency, recipientId: real.recipientId, quoteId: real.quoteId, nonce: nonce,
                    timestamp: real.timestamp),
            ]

            for payload in tampered {
                let response = try await harness.sendConfirm(session, id: transfer.id, payload: payload)
                XCTAssertEqual(response.envelope?.code, "payload_mismatch")
            }
            try await assertNothingMoved(harness, session, transfer)
        }
    }

    /// A session from before device binding has no device, so it can't ask to sign or confirm.
    func testSessionWithoutADeviceCantSign() async throws {
        try await withApp { harness in
            let session = try await harness.login()
            let transfer = try await created(harness, session)
            try await harness.app.db.sqlDatabase().update("tokens")
                .set("deviceId", to: SQLLiteral.null).run()

            let challenge = try await harness.send(
                .POST, "/v1/transfers/\(transfer.id)/challenge", token: session.accessToken)
            let confirm = try await harness.sendConfirm(
                session, id: transfer.id, payload: harness.payload(for: transfer, nonce: "n"))

            XCTAssertEqual(challenge.envelope?.code, "device_not_bound")
            XCTAssertEqual(confirm.envelope?.code, "device_not_bound")
            try await assertNothingMoved(harness, session, transfer)
        }
    }

    func testChallengesPerTransferAreCapped() async throws {
        try await withApp { harness in
            let session = try await harness.login()
            let id = UUID().uuidString
            for _ in 0..<TransfersController.maxLiveChallenges {
                _ = try await challenge(harness, session, id)
            }

            let response = try await harness.send(.POST, "/v1/transfers/\(id)/challenge", token: session.accessToken)
            harness.advance(61)
            let later = try await harness.send(.POST, "/v1/transfers/\(id)/challenge", token: session.accessToken)

            XCTAssertEqual(response.status, .tooManyRequests)
            XCTAssertEqual(later.status, .created)
        }
    }

    // MARK: - Helpers

    private func created(_ harness: Harness, _ session: SignedIn) async throws -> TransferDTO {
        try await TransferConfirmTests().created(harness, session.accessToken, minor: 10_000)
    }

    private func challenge(_ harness: Harness, _ session: SignedIn, _ id: String) async throws -> String {
        let response = try await harness.send(.POST, "/v1/transfers/\(id)/challenge", token: session.accessToken)
        XCTAssertEqual(response.status, .created)
        return try response.content.decode(ChallengeDTO.self).nonce
    }

    /// Signs `signed` but sends the bytes of `sent`.
    private func sendSwapped(
        _ harness: Harness,
        _ session: SignedIn,
        _ id: String,
        signed: ConfirmPayload,
        sent: ConfirmPayload
    ) async throws -> XCTHTTPResponse {
        let signature = try session.key.signature(for: try DeviceBindingTests.encoded(signed))
        return try await harness.send(
            .POST,
            "/v1/transfers/\(id)/confirm",
            token: session.accessToken,
            json: ConfirmRequest(
                payload: try DeviceBindingTests.encoded(sent).base64EncodedString(),
                signature: signature.derRepresentation.base64EncodedString(),
                assertion: nil
            )
        )
    }

    private func assertNothingMoved(_ harness: Harness, _ session: SignedIn, _ transfer: TransferDTO) async throws {
        let current = try await TransferConfirmTests().status(harness, session.accessToken, transfer.id)
        XCTAssertEqual(current.status, "awaiting_confirmation")
        let balance = try await TransferConfirmTests().balanceMinor(harness, "acc_sgd")
        XCTAssertEqual(balance, 1_250_000)
    }
}
