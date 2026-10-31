import Foundation
import Testing
import os

@testable import NetworkingKit

/// Answers requests in-process. Handlers are keyed by host, so tests running in
/// parallel each use their own host and never see each other's stubs.
final class StubURLProtocol: URLProtocol {
    struct Reply: Sendable {
        var status: Int
        var headers: [String: String] = [:]
        var body = Data()
        /// Sends a redirect to this URL instead of a final response.
        var redirect: URL?
    }

    typealias Handler = @Sendable (URLRequest) throws -> Reply

    private static let handlers = OSAllocatedUnfairLock<[String: Handler]>(initialState: [:])

    static func register(host: String, handler: @escaping Handler) {
        handlers.withLock { $0[host] = handler }
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host() ?? ""
        guard let handler = Self.handlers.withLock({ $0[host] }), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let reply = try handler(request)
            guard
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: reply.status,
                    httpVersion: nil,
                    headerFields: reply.headers
                )
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            if let target = reply.redirect {
                // If the session declines, the 3xx below becomes the final response.
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite struct URLSessionTransportTests {
    @Test func returnsStatusHeadersAndBodyForAnyStatus() async throws {
        let host = "status.\(UUID().uuidString).test"
        StubURLProtocol.register(host: host) { request in
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: HTTPHeader.idempotencyKey) == "k1")
            return StubURLProtocol.Reply(
                status: 422,
                headers: ["X-Request-ID": "req_1"],
                body: Data(#"{"code":"quote_expired"}"#.utf8)
            )
        }
        let transport = URLSessionTransport(session: StubURLProtocol.session())
        let url = try #require(URL(string: "https://\(host)/v1/transfers"))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("k1", forHTTPHeaderField: HTTPHeader.idempotencyKey)

        let response = try await transport.send(request)

        #expect(response.statusCode == 422)
        #expect(response.header("x-request-id") == "req_1")
        #expect(response.body == Data(#"{"code":"quote_expired"}"#.utf8))
    }

    @Test func urlErrorsBecomeTransportErrors() async throws {
        let host = "offline.\(UUID().uuidString).test"
        StubURLProtocol.register(host: host) { _ in throw URLError(.notConnectedToInternet) }
        let transport = URLSessionTransport(session: StubURLProtocol.session())
        let url = try #require(URL(string: "https://\(host)/v1/accounts"))

        await #expect(throws: HTTPError.transport(.notConnectedToInternet)) {
            try await transport.send(URLRequest(url: url))
        }
    }

    @Test func fullClientRoundTripThroughURLSession() async throws {
        let host = "roundtrip.\(UUID().uuidString).test"
        StubURLProtocol.register(host: host) { request in
            let hasID = request.value(forHTTPHeaderField: HTTPHeader.requestID) != nil
            return StubURLProtocol.Reply(status: hasID ? 200 : 400, body: Data(#"{"id":"acc_1"}"#.utf8))
        }
        let client = HTTPClient(
            baseURL: try #require(URL(string: "https://\(host)")),
            transport: URLSessionTransport(session: StubURLProtocol.session()),
            interceptors: HTTPClient.standardInterceptors(auth: nil)
        )

        let account = try await client.send(
            Endpoint<Account>(request: HTTPRequest(method: .get, path: "/v1/accounts/acc_1")))

        #expect(account == Account(id: "acc_1"))
    }

    @Test func redirectsAreNotFollowed() async throws {
        // Login and refresh bodies hold the password or refresh token, and URLSession
        // resends the body to the redirect target.
        let origin = "redirect.\(UUID().uuidString).test"
        let target = "elsewhere.\(UUID().uuidString).test"
        let targetURL = try #require(URL(string: "https://\(target)/v1/auth/refresh"))
        StubURLProtocol.register(host: origin) { _ in
            StubURLProtocol.Reply(status: 307, headers: ["Location": targetURL.absoluteString], redirect: targetURL)
        }
        StubURLProtocol.register(host: target) { _ in StubURLProtocol.Reply(status: 200) }
        let url = try #require(URL(string: "https://\(origin)/v1/auth/refresh"))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"refreshToken":"secret"}"#.utf8)

        // Control: a plain session on the same stub does follow it, so the check below means something.
        let (_, followed) = try await StubURLProtocol.session().data(for: request)
        #expect((followed as? HTTPURLResponse)?.url?.host() == target)

        let response = try await URLSessionTransport(session: StubURLProtocol.session()).send(request)

        #expect(response.statusCode == 307)
    }
}
