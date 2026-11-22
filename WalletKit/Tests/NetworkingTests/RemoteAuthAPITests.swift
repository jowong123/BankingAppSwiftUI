import Domain
import Foundation
import NetworkingKit
import Testing

@testable import Networking

@Suite struct RemoteAuthAPITests {
    let tokensJSON = #"{"accessToken":"a","refreshToken":"r","expiresIn":900}"#

    func makeAuthAPI(_ transport: StubTransport) throws -> RemoteAuthAPI {
        RemoteAuthAPI(
            client: HTTPClient(
                baseURL: try #require(URL(string: "https://api.example.test")),
                transport: transport,
                interceptors: HTTPClient.standardInterceptors(
                    auth: nil,
                    retry: RetryInterceptor(
                        sleep: { _ in },
                        unitRandom: {
                            0
                        })
                )
            )
        )
    }

    @Test func loginSendsNoBearerTokenAndReturnsABindingToken() async throws {
        let transport = StubTransport([status(200, #"{"bindingToken":"b","expiresIn":300}"#)])

        let token = try await makeAuthAPI(transport).login(email: "demo@wallet.test", password: "pw")

        #expect(token == BindingToken("b"))
        let request = try #require(await transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.url?.path() == "/v1/auth/login")
    }

    @Test func bindDeviceSendsTheKeyAndAttestationAndReturnsTheSession() async throws {
        let bound = #"{"deviceId":"dev-1","accessToken":"a","refreshToken":"r","expiresIn":900}"#
        let transport = StubTransport([status(200, bound)])
        let request = DeviceBindingRequest(
            bindingToken: BindingToken("b"),
            signingKey: Data([4, 1, 2]),
            attestation: DeviceAttestation(keyID: "key-id", object: Data([0xA3]))
        )

        let session = try await makeAuthAPI(transport).bindDevice(request)

        #expect(session == BoundSession(deviceID: "dev-1", tokens: SessionTokens(accessToken: "a", refreshToken: "r")))
        let sent = try #require(await transport.requests.first)
        #expect(sent.url?.path() == "/v1/devices")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == nil)
        let json = try body(of: sent)
        #expect(json["bindingToken"] as? String == "b")
        #expect(json["signingKey"] as? String == "BAEC")
        #expect((json["attestation"] as? [String: Any])?["keyId"] as? String == "key-id")
    }

    /// The binding token works once, so a resend after a lost response can only fail.
    @Test func bindDeviceIsNeverRetried() async throws {
        let transport = StubTransport([.failure(.transport(.timedOut)), status(200, "{}")])

        await #expect(throws: AuthError.offline) {
            try await makeAuthAPI(transport).bindDevice(
                DeviceBindingRequest(bindingToken: BindingToken("b"), signingKey: nil, attestation: nil))
        }
        #expect(await transport.requests.count == 1)
    }

    @Test(arguments: [401, 422])
    func refusedDeviceMeansSigningInAgain(status code: Int) async throws {
        let refused = #"{"code":"attestation_invalid","message":"No","requestId":"r"}"#
        let transport = StubTransport([status(code, refused)])

        await #expect(throws: AuthError.deviceSetupFailed) {
            try await makeAuthAPI(transport).bindDevice(
                DeviceBindingRequest(bindingToken: BindingToken("b"), signingKey: nil, attestation: nil))
        }
    }

    /// Refresh tokens rotate; a resend would look like theft and sign the user out (ADR-016).
    @Test func refreshIsNeverRetried() async throws {
        let transport = StubTransport([.failure(.transport(.timedOut)), status(200, tokensJSON)])

        await #expect(throws: AuthError.offline) {
            try await makeAuthAPI(transport).refresh(refreshToken: "r")
        }
        #expect(await transport.requests.count == 1)
    }

    @Test func logoutPostsTheRefreshTokenAndAcceptsAnEmpty204() async throws {
        let transport = StubTransport([status(204)])

        try await makeAuthAPI(transport).logout(refreshToken: "r")

        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "/v1/auth/logout")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(try body(of: request)["refreshToken"] as? String == "r")
    }

    @Test func wrongPasswordIsInvalidCredentials() async throws {
        let envelope = #"{"code":"invalid_credentials","message":"","requestId":"req_1"}"#

        await #expect(throws: AuthError.invalidCredentials) {
            try await makeAuthAPI(StubTransport([status(401, envelope)])).login(email: "a@b.test", password: "x")
        }
    }

    @Test(arguments: [
        (
            APIError.server(status: 401, code: "invalid_refresh_token", message: "", requestID: nil),
            AuthError.sessionExpired
        ),
        (.server(status: 400, code: "bad_request", message: "", requestID: nil), .sessionExpired),
        (.http(status: 403), .sessionExpired),
        (.http(status: 429), .unavailable),
        (.http(status: 408), .unavailable),
        (.http(status: 503), .unavailable),
        (.transport(.notConnectedToInternet), .offline),
        (.transport(.cannotFindHost), .unavailable),
        (.transport(.serverCertificateUntrusted), .unavailable),
        (.cancelled, .cancelled),
    ])
    func onlyADefiniteRefusalEndsTheSession(error: APIError, expected: AuthError) {
        #expect(RemoteAuthAPI.refreshError(error) == expected)
    }

    @Test(arguments: [
        (
            APIError.server(status: 401, code: "invalid_credentials", message: "", requestID: nil),
            AuthError.invalidCredentials
        ),
        (.transport(.timedOut), .offline),
        (.transport(.networkConnectionLost), .offline),
        // The backend isn't running: the phone's connection is fine.
        (.transport(.cannotConnectToHost), .unavailable),
        (.transport(.badServerResponse), .unavailable),
        (.http(status: 500), .unavailable),
    ])
    func loginErrorsMapToWhatTheUserCanDo(error: APIError, expected: AuthError) {
        #expect(RemoteAuthAPI.loginError(error) == expected)
    }
}
