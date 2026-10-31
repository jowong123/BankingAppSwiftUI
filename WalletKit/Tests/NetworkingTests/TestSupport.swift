import Domain
import Foundation
import NetworkingKit
import Testing

@testable import Networking

/// Records requests and answers from a script; the last answer repeats.
actor StubTransport: HTTPTransport {
    private var script: [Result<HTTPResponse, HTTPError>]
    private(set) var requests: [URLRequest] = []

    init(_ script: [Result<HTTPResponse, HTTPError>]) {
        self.script = script
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        let next = script.count > 1 ? script.removeFirst() : script[0]
        return try next.get()
    }
}

func status(_ code: Int, _ body: String = "") -> Result<HTTPResponse, HTTPError> {
    .success(HTTPResponse(statusCode: code, body: Data(body.utf8)))
}

struct FakeTokens: SessionTokenProvider {
    var token: String? = "access_1"
    var refreshed: String?
    /// Thrown by `refreshAccessToken` when `refreshed` is nil.
    var refreshError: any Error = SessionRefreshError.noSession

    func accessToken() async -> String? { token }

    func refreshAccessToken() async throws -> String {
        guard let refreshed else { throw refreshError }
        return refreshed
    }
}

/// A `WalletAPI` over the stub, with the real interceptor chain (including the app's
/// refresh error mapping) but no backoff sleep.
func makeAPI(_ transport: StubTransport, tokens: FakeTokens = FakeTokens()) throws -> WalletAPI {
    let auth = WalletAPI.authInterceptor(tokens: tokens)
    let retry = RetryInterceptor(sleep: { _ in }, unitRandom: { 0 })
    let client = HTTPClient(
        baseURL: try #require(URL(string: "https://api.example.test")),
        transport: transport,
        interceptors: HTTPClient.standardInterceptors(auth: auth, retry: retry)
    )
    return WalletAPI(client: client)
}

func json(_ data: Data?) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: try #require(data))
    return try #require(object as? [String: Any])
}

/// URLSession moves the body into a stream; the stub transport sees `httpBody` directly.
func body(of request: URLRequest) throws -> [String: Any] {
    try json(request.httpBody)
}
