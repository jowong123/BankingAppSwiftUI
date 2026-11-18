import Crypto
import SQLKit
import XCTVapor

@testable import WalletBackend

final class DeviceBindingTests: XCTestCase {
    /// Login alone is no session: the binding token can't call the API.
    func testBindingTokenIsNotABearerToken() async throws {
        try await withApp { harness in
            let token = try await harness.bindingToken()

            let response = try await harness.send(.GET, "/v1/accounts", token: token)

            XCTAssertEqual(response.status, .unauthorized)
        }
    }

    func testBindingTokenWorksOnce() async throws {
        try await withApp { harness in
            let token = try await harness.bindingToken()
            let request = DeviceBindingRequest(bindingToken: token, signingKey: Self.newKey(), attestation: nil)

            let first = try await harness.bind(request)
            let second = try await harness.bind(request)

            XCTAssertEqual(first.status, .ok)
            XCTAssertEqual(second.status, .unauthorized)
            XCTAssertEqual(second.envelope?.code, "invalid_binding_token")
        }
    }

    func testBindingTokenExpiresAfterFiveMinutes() async throws {
        try await withApp { harness in
            let token = try await harness.bindingToken()
            harness.advance(5 * 60 + 1)

            let response = try await harness.bind(
                DeviceBindingRequest(bindingToken: token, signingKey: Self.newKey(), attestation: nil))

            XCTAssertEqual(response.envelope?.code, "invalid_binding_token")
        }
    }

    /// No Face ID on the phone: it can view, but can't ask to sign a transfer.
    func testDeviceWithoutASigningKeyCanViewButNotSend() async throws {
        try await withApp { harness in
            let response = try await harness.bind(
                DeviceBindingRequest(bindingToken: try await harness.bindingToken(), signingKey: nil, attestation: nil))
            let bound = try response.content.decode(BoundDevice.self)

            let accounts = try await harness.send(.GET, "/v1/accounts", token: bound.accessToken)
            let challenge = try await harness.send(
                .POST, "/v1/transfers/\(UUID().uuidString)/challenge", token: bound.accessToken)

            XCTAssertEqual(accounts.status, .ok)
            XCTAssertEqual(challenge.status, .forbidden)
            XCTAssertEqual(challenge.envelope?.code, "device_not_bound")
        }
    }

    func testMalformedSigningKeyIsRefusedAndTheTokenKept() async throws {
        try await withApp { harness in
            let token = try await harness.bindingToken()

            let bad = try await harness.bind(
                DeviceBindingRequest(bindingToken: token, signingKey: "bm90IGEga2V5", attestation: nil))
            let good = try await harness.bind(
                DeviceBindingRequest(bindingToken: token, signingKey: Self.newKey(), attestation: nil))

            XCTAssertEqual(bad.envelope?.code, "invalid_request")
            XCTAssertEqual(good.status, .ok)
        }
    }

    /// A refreshed session stays on its device, so it can still sign.
    func testRefreshKeepsTheDevice() async throws {
        try await withApp { harness in
            let session = try await harness.login()
            let response = try await harness.send(
                .POST, "/v1/auth/refresh", json: RefreshRequest(refreshToken: session.refreshToken))
            let refreshed = try response.content.decode(SessionTokens.self)

            let challenge = try await harness.send(
                .POST, "/v1/transfers/\(UUID().uuidString)/challenge", token: refreshed.accessToken)

            XCTAssertEqual(challenge.status, .created)
        }
    }

    // MARK: - App Attest required

    func testAttestationIsRequiredOutsideSandboxMode() async throws {
        let attest = try FakeAppAttest()
        try await withApp(attestation: .apple(attest.verifier())) { harness in
            let response = try await harness.bind(
                DeviceBindingRequest(
                    bindingToken: try await harness.bindingToken(), signingKey: Self.newKey(), attestation: nil))

            XCTAssertEqual(response.status, .unprocessableEntity)
            XCTAssertEqual(response.envelope?.code, "attestation_invalid")
        }
    }

    /// The attestation vouches for this binding token and this signing key only.
    func testAttestationForAnotherSigningKeyIsRefused() async throws {
        let attest = try FakeAppAttest()
        try await withApp(attestation: .apple(attest.verifier())) { harness in
            let token = try await harness.bindingToken()
            let appKey = FakeAppAttest.Key()
            let attested = try attest.attestation(
                for: appKey,
                clientData: DevicesController.clientData(bindingToken: token, signingKey: Self.newKey())
            )

            let response = try await harness.bind(
                DeviceBindingRequest(
                    bindingToken: token,
                    signingKey: Self.newKey(),
                    attestation: AttestationDTO(
                        keyId: appKey.keyID.base64EncodedString(), object: attested.base64EncodedString())
                ))

            XCTAssertEqual(response.envelope?.code, "attestation_invalid")
        }
    }

    /// The whole path on an attested device: bind, then a confirm needs a fresh assertion.
    func testAttestedDeviceNeedsAnAssertionOnEveryConfirm() async throws {
        let attest = try FakeAppAttest()
        try await withApp(attestation: .apple(attest.verifier())) { harness in
            let signingKey = P256.Signing.PrivateKey()
            let appKey = FakeAppAttest.Key()
            let session = try await Self.bindAttested(harness, attest, signingKey: signingKey, appKey: appKey)
            let transfer = try await TransferConfirmTests().created(harness, session.accessToken, minor: 10_000)

            let challenge = try await harness.send(
                .POST, "/v1/transfers/\(transfer.id)/challenge", token: session.accessToken)
            let nonce = try challenge.content.decode(ChallengeDTO.self).nonce
            let payload = harness.payload(for: transfer, nonce: nonce)
            let missing = try await harness.sendConfirm(session, id: transfer.id, payload: payload)
            let assertion = try attest.assertion(for: appKey, clientData: try Self.encoded(payload), counter: 1)
            let confirmed = try await harness.sendConfirm(
                session, id: transfer.id, payload: payload, assertion: assertion.base64EncodedString())

            XCTAssertEqual(missing.envelope?.code, "assertion_invalid")
            XCTAssertEqual(try confirmed.content.decode(TransferDTO.self).status, "processing")
        }
    }

    /// A device bound while the server ran in sandbox mode has no App Attest key. After a
    /// restart in apple mode it must not keep confirming without assertions.
    func testUnattestedDeviceIsRefusedInAppleMode() async throws {
        let attest = try FakeAppAttest()
        let sandbox = TransfersController(clock: .system, attestation: .sandbox)
        let apple = TransfersController(clock: .system, attestation: .apple(attest.verifier()))
        let device = DeviceRow(
            id: "d", userId: "u", signingKey: Data([4]), attestKeyId: nil, attestPublicKey: nil, signCount: 0,
            createdAt: 0)

        XCTAssertTrue(sandbox.isTrusted(device))
        XCTAssertFalse(apple.isTrusted(device))
    }

    func testAttestationModeIsStrictByDefault() throws {
        XCTAssertThrowsError(try AttestationMode.from(mode: nil, appID: nil, environment: nil))
        XCTAssertThrowsError(try AttestationMode.from(mode: "off", appID: "T.app", environment: nil))
        XCTAssertThrowsError(try AttestationMode.from(mode: nil, appID: "T.app", environment: "dev"))
        guard case .apple(let verifier) = try AttestationMode.from(mode: nil, appID: "T.app", environment: nil) else {
            return XCTFail("expected apple mode")
        }
        XCTAssertFalse(verifier.allowsDevelopment)
        guard
            case .apple(let development) = try AttestationMode.from(
                mode: nil, appID: "T.app", environment: "development")
        else {
            return XCTFail("expected apple mode")
        }
        XCTAssertTrue(development.allowsDevelopment)
    }

    // MARK: - Helpers

    static func newKey() -> String {
        P256.Signing.PrivateKey().publicKey.x963Representation.base64EncodedString()
    }

    static func encoded(_ payload: ConfirmPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    private static func bindAttested(
        _ harness: Harness,
        _ attest: FakeAppAttest,
        signingKey: P256.Signing.PrivateKey,
        appKey: FakeAppAttest.Key
    ) async throws -> SignedIn {
        let token = try await harness.bindingToken()
        let publicKey = signingKey.publicKey.x963Representation.base64EncodedString()
        let attested = try attest.attestation(
            for: appKey,
            clientData: DevicesController.clientData(bindingToken: token, signingKey: publicKey)
        )
        let response = try await harness.bind(
            DeviceBindingRequest(
                bindingToken: token,
                signingKey: publicKey,
                attestation: AttestationDTO(
                    keyId: appKey.keyID.base64EncodedString(), object: attested.base64EncodedString())
            ))
        XCTAssertEqual(response.status, .ok)
        let bound = try response.content.decode(BoundDevice.self)
        return SignedIn(
            accessToken: bound.accessToken,
            refreshToken: bound.refreshToken,
            expiresIn: bound.expiresIn,
            deviceId: bound.deviceId,
            key: signingKey
        )
    }
}
