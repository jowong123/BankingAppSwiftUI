import Crypto
import SQLKit
import Vapor

/// `POST /v1/devices`: binds this device to the user and starts the session (SPEC section 6).
///
/// The app sends the binding token from login, the public half of its Secure Enclave key,
/// and an App Attest attestation whose client data covers both. Everything is checked
/// before the token is used up, and the token, the device and the session are written in
/// one transaction: the token works once, for one device.
struct DevicesController: Sendable {
    let clock: BackendClock
    let attestation: AttestationMode

    @Sendable func bind(_ request: Request) async throws -> BoundDevice {
        let body = try request.content.decode(DeviceBindingRequest.self)
        // A cheap look-up first, so junk can't make the server check certificate chains.
        guard
            try await request.sql.select().column("tokenHash").from("tokens")
                .where("tokenHash", .equal, Tokens.hash(body.bindingToken))
                .where("kind", .equal, "binding")
                .where("revoked", .equal, 0)
                .where("expiresAt", .greaterThan, clock.nowMillis)
                .first() != nil
        else {
            throw APIFailure.invalidBindingToken
        }
        let signingKey = try body.signingKey.map(Self.signingKey)
        let attested = try await attest(body, signingKey: signingKey)
        let now = clock.nowMillis
        let deviceID = UUID().uuidString.lowercased()

        let issued: SessionTokens = try await request.db.transaction { database in
            let sql = try database.sqlDatabase()
            guard
                let token = try await sql.update("tokens")
                    .set("revoked", to: 1)
                    .where("tokenHash", .equal, Tokens.hash(body.bindingToken))
                    .where("kind", .equal, "binding")
                    .where("revoked", .equal, 0)
                    .where("expiresAt", .greaterThan, now)
                    .returning("*")
                    .first(decoding: TokenRow.self)
            else {
                throw APIFailure.invalidBindingToken
            }
            try await sql.insert(into: "devices").model(
                DeviceRow(
                    id: deviceID,
                    userId: token.userId,
                    signingKey: signingKey?.x963Representation,
                    attestKeyId: attested?.keyID,
                    attestPublicKey: attested?.key.publicKey,
                    signCount: Int64(attested?.key.counter ?? 0),
                    createdAt: now
                )
            ).run()
            return try await AuthController.issueTokens(
                userID: token.userId, deviceID: deviceID, clock: clock, sql: sql)
        }
        return BoundDevice(
            deviceId: deviceID,
            accessToken: issued.accessToken,
            refreshToken: issued.refreshToken,
            expiresIn: issued.expiresIn
        )
    }

    /// What the app passes as App Attest client data at binding: the binding token and the
    /// signing key, so the attestation vouches for this key and can't be replayed for another.
    static func clientData(bindingToken: String, signingKey: String?) -> Data {
        Data("\(bindingToken).\(signingKey ?? "")".utf8)
    }

    private func attest(_ body: DeviceBindingRequest, signingKey: P256.Signing.PublicKey?) async throws
        -> (keyID: String, key: AppAttestVerifier.AttestedKey)?
    {
        guard case .apple(let verifier) = attestation else {
            return nil
        }
        guard let attestation = body.attestation,
            let keyID = Data(base64Encoded: attestation.keyId),
            let object = Data(base64Encoded: attestation.object)
        else {
            throw APIFailure.attestationInvalid
        }
        do {
            let key = try await verifier.verifyAttestation(
                object,
                keyID: keyID,
                clientData: Self.clientData(bindingToken: body.bindingToken, signingKey: body.signingKey)
            )
            return (attestation.keyId, key)
        } catch {
            throw APIFailure.attestationInvalid
        }
    }

    private static func signingKey(_ base64: String) throws -> P256.Signing.PublicKey {
        guard let data = Data(base64Encoded: base64),
            let key = try? P256.Signing.PublicKey(x963Representation: data)
        else {
            throw APIFailure.invalid("signingKey must be a base64 X9.63 P-256 public key.")
        }
        return key
    }
}
