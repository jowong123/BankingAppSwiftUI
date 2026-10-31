import Foundation
import NetworkingKit

let baseURL = URL(string: "https://api.example.test")

/// Transport that records every request and answers from a script.
/// The last scripted answer repeats once the script runs out.
actor StubTransport: HTTPTransport {
    typealias Handler = @Sendable (URLRequest) async throws -> HTTPResponse

    private var script: [Result<HTTPResponse, HTTPError>]
    private let handler: Handler?
    private(set) var requests: [URLRequest] = []

    init(_ script: [Result<HTTPResponse, HTTPError>]) {
        self.script = script
        self.handler = nil
    }

    init(handler: @escaping Handler) {
        self.script = []
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        if let handler { return try await handler(request) }
        let next = script.count > 1 ? script.removeFirst() : script[0]
        return try next.get()
    }

    func header(_ name: String, at index: Int) -> String? {
        requests[index].value(forHTTPHeaderField: name)
    }
}

/// Records backoff delays instead of sleeping, so retry tests run instantly.
actor SleepRecorder {
    private(set) var delays: [Duration] = []

    func sleep(_ duration: Duration) {
        delays.append(duration)
    }
}

func status(_ code: Int, _ body: String = "") -> Result<HTTPResponse, HTTPError> {
    .success(HTTPResponse(statusCode: code, body: Data(body.utf8)))
}

func makeClient(
    _ transport: StubTransport,
    interceptors: [any Interceptor]
) throws -> HTTPClient {
    HTTPClient(baseURL: try requireBaseURL(), transport: transport, interceptors: interceptors)
}

func requireBaseURL() throws -> URL {
    guard let baseURL else { throw HTTPError.invalidRequest }
    return baseURL
}

/// A retry interceptor that doesn't sleep and always picks the full backoff (random = 1).
func instantRetry(_ recorder: SleepRecorder = SleepRecorder(), maxAttempts: Int = 3) -> RetryInterceptor {
    RetryInterceptor(
        policy: RetryPolicy(maxAttempts: maxAttempts),
        sleep: { await recorder.sleep($0) },
        unitRandom: { 1 }
    )
}

struct Account: Decodable, Equatable {
    let id: String
}
