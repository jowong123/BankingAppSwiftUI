import CryptoKit
import Domain
import Foundation
import LocalAuthentication
import Testing

@testable import WalletSecurity

/// The signing key's rules (SPEC section 6), on `SoftwareKey`: the simulator's stand-in obeys
/// the same contract as the Secure Enclave key, which can only be tried on a phone.
@Suite struct DeviceSigningTests {
    let storage = InMemoryStore()
    let biometrics = FakeBiometrics()

    var key: SoftwareKey {
        SoftwareKey(store: storage, biometrics: biometrics)
    }

    @Test func signatureVerifiesWithThePublicKeyFromBinding() async throws {
        let publicKey = try P256.Signing.PublicKey(x963Representation: try key.make())
        let message = Data("approve".utf8)

        let signature = try await key.sign(message, reason: "Approve")

        #expect(publicKey.isValidSignature(try P256.Signing.ECDSASignature(derRepresentation: signature), for: message))
        #expect(biometrics.prompts == 1)
    }

    /// Someone adds their face: the key no longer signs, with no prompt shown.
    @Test func enrolmentChangeInvalidatesTheKey() async throws {
        _ = try key.make()
        biometrics.enroll("face-B")

        #expect(key.availability() == .keyInvalidated)
        await #expect(throws: SigningError.keyInvalidated) {
            try await key.sign(Data(), reason: "Approve")
        }
        #expect(biometrics.prompts == 0)
    }

    /// The enrolment changes between the check and the prompt.
    @Test func enrolmentChangedDuringThePromptIsRefused() async throws {
        _ = try key.make()
        biometrics.changeDuringPrompt(to: "face-B")

        await #expect(throws: SigningError.keyInvalidated) {
            try await key.sign(Data(), reason: "Approve")
        }
    }

    @Test func noFaceIDMeansNoKey() {
        biometrics.setAvailable(false)

        #expect(!key.canMake())
        #expect(throws: SigningError.biometryNotSetUp) {
            try key.make()
        }
        #expect(key.availability() == .biometryNotSetUp)
    }

    @Test func cancelledPromptSignsNothing() async throws {
        _ = try key.make()
        biometrics.setResult(.failure(.cancelled))

        await #expect(throws: SigningError.cancelled) {
            try await key.sign(Data(), reason: "Approve")
        }
    }

    /// How the Secure Enclave key reads Face ID's answers: a cancel shows nothing, no faces
    /// enrolled any more means the key is gone, anything else is a failed attempt.
    @Test func faceIDErrorsMapToWhatTheScreenDoes() {
        #expect(SecureEnclaveKey.signingError(for: .userCancel) == .cancelled)
        #expect(SecureEnclaveKey.signingError(for: .userFallback) == .cancelled)
        #expect(SecureEnclaveKey.signingError(for: .systemCancel) == .cancelled)
        #expect(SecureEnclaveKey.signingError(for: .biometryNotEnrolled) == .keyInvalidated)
        #expect(SecureEnclaveKey.signingError(for: .authenticationFailed) == .failed)
        #expect(SecureEnclaveKey.signingError(for: .biometryLockout) == .failed)
    }

    @Test func removeDeletesTheKeyAndItsEnrolment() throws {
        _ = try key.make()

        key.remove()

        #expect(storage.keys.isEmpty)
    }

    /// The exact bytes the server verifies: sorted keys, no whitespace, minor units, millis.
    @Test func canonicalPayloadIsStable() throws {
        let payload = ConfirmPayload(
            transferID: try #require(UUID(uuidString: "6F1C2E1A-0000-4000-8000-000000000001")),
            amountMinor: 10_000,
            currency: .sgd,
            recipientID: "rcp_alice_usd",
            quoteID: "q_1",
            nonce: "n/1",
            timestamp: Date(timeIntervalSince1970: 1_800_000_000.1234)
        )

        let text = try #require(String(bytes: try CanonicalPayload.encode(payload), encoding: .utf8))

        #expect(
            text
                == #"{"amountMinor":10000,"currency":"SGD","nonce":"n/1","quoteId":"q_1","recipientId":"rcp_alice_usd","#
                + #""timestamp":1800000000123,"transferId":"6f1c2e1a-0000-4000-8000-000000000001"}"#
        )
    }

    /// On an attested device the approval also carries an App Attest assertion over the same bytes.
    @Test func signerAddsAnAssertionOverThePayload() async throws {
        let attestor = FakeAttestor(supported: true)
        _ = try key.make()
        try storage.set(
            try JSONEncoder().encode(DeviceRecord(deviceID: "dev-1", attestKeyID: "attest-key")),
            for: DeviceRecord.storeKey)
        let signer = TransferSigner(key: key, attestor: attestor, store: storage)

        let signed = try await signer.sign(Self.payload, reason: "Approve")

        #expect(signed.assertion == Data("assertion".utf8))
        #expect(attestor.assertedHashes == [Data(SHA256.hash(data: signed.payload))])
    }

    @Test func signerWithoutAppAttestSendsNoAssertion() async throws {
        _ = try key.make()
        let signer = TransferSigner(key: key, attestor: FakeAttestor(supported: false), store: storage)

        let signed = try await signer.sign(Self.payload, reason: "Approve")

        #expect(signed.assertion == nil)
    }

    static let payload = ConfirmPayload(
        transferID: UUID(),
        amountMinor: 10_000,
        currency: .sgd,
        recipientID: "rcp",
        quoteID: "q",
        nonce: "n",
        timestamp: Date(timeIntervalSince1970: 0)
    )
}

/// Signing in binds the device (SPEC section 6).
@Suite struct DeviceBindingTests {
    @Test func signInSendsTheNewPublicKey() async throws {
        let api = FakeAuthAPI()
        let storage = InMemoryStore()
        let store = makeStore(api: api, storage: storage)

        _ = try await store.login(email: "demo@wallet.test", password: "pw")

        let request = try #require(await api.bindRequests.first)
        #expect(request.bindingToken == BindingToken("b1"))
        #expect(request.signingKey?.count == 65)
        #expect(request.attestation == nil)
        #expect(storage.raw(DeviceRecord.storeKey) != nil)
    }

    /// No Face ID: bound without a key, so the device can view but not send.
    @Test func signInWithoutFaceIDBindsWithoutAKey() async throws {
        let api = FakeAuthAPI()
        let biometrics = FakeBiometrics()
        biometrics.setAvailable(false)
        let store = makeStore(api: api, biometrics: biometrics)

        #expect(try await store.login(email: "demo@wallet.test", password: "pw") == .needsPIN)

        #expect(await api.bindRequests.first?.signingKey == nil)
    }

    /// App Attest vouches for this binding token and this key, nothing else.
    @Test func attestationCoversTheTokenAndTheKey() async throws {
        let api = FakeAuthAPI()
        let attestor = FakeAttestor(supported: true)
        let store = makeStore(api: api, attestor: attestor)

        _ = try await store.login(email: "demo@wallet.test", password: "pw")

        let request = try #require(await api.bindRequests.first)
        let expected = DeviceBindingRequest.clientData(bindingToken: BindingToken("b1"), signingKey: request.signingKey)
        #expect(request.attestation == DeviceAttestation(keyID: "attest-key", object: Data("attestation".utf8)))
        #expect(attestor.attestedHashes == [Data(SHA256.hash(data: expected))])
    }

    /// Face ID is set up but the key can't be stored: an error, not a quiet "view only".
    @Test func keyThatCantBeMadeFailsSignInAndLeavesNothing() async throws {
        let api = FakeAuthAPI()
        let storage = InMemoryStore()
        storage.fail(writes: true)
        let store = makeStore(api: api, storage: storage)

        await #expect(throws: AuthError.deviceSetupFailed) {
            try await store.login(email: "demo@wallet.test", password: "pw")
        }
        storage.fail()
        #expect(storage.keys.isEmpty)
        #expect(await api.bindRequests.isEmpty)
    }

    @Test func refusedDeviceLeavesNothingBehind() async throws {
        let api = FakeAuthAPI()
        await api.setBind(.failure(.deviceSetupFailed))
        let storage = InMemoryStore()
        let store = makeStore(api: api, storage: storage)

        await #expect(throws: AuthError.deviceSetupFailed) {
            try await store.login(email: "demo@wallet.test", password: "pw")
        }
        #expect(storage.keys.isEmpty)
        #expect(await store.currentState() == .signedOut)
    }

    @Test func signOutDeletesTheSigningKey() async throws {
        let storage = InMemoryStore()
        let store = try await lockedStore(storage: storage)

        _ = await store.signOut()

        #expect(storage.keys.isEmpty)
    }

    /// A session saved before device binding (Phase 6) is wiped at launch: it has no key.
    @Test func sessionWithoutABoundDeviceIsWipedAtLaunch() async throws {
        let storage = InMemoryStore()
        _ = try await lockedStore(storage: storage)
        try storage.remove(DeviceRecord.storeKey)

        #expect(await makeStore(storage: storage).restore() == .signedOut)
        #expect(storage.keys.isEmpty)
    }
}
