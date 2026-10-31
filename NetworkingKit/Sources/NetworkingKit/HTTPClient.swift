import Foundation

/// Runs requests through an ordered interceptor chain, then the transport.
///
/// `interceptors[0]` is outermost: it sees the request first and the response last.
/// The usual order is in `HTTPClient.standardInterceptors` (ADR-012).
public struct HTTPClient: Sendable {
    private let baseURL: URL
    private let transport: any HTTPTransport
    private let interceptors: [any Interceptor]

    public init(baseURL: URL, transport: any HTTPTransport, interceptors: [any Interceptor]) {
        self.baseURL = baseURL
        self.transport = transport
        self.interceptors = interceptors
    }

    /// Sends the request and decodes a 2xx body. A non-2xx response throws
    /// `HTTPError.status` with the body, so the caller can decode its error envelope.
    public func send<Response>(_ endpoint: Endpoint<Response>) async throws -> Response {
        let response = try await execute(endpoint.request)
        guard response.isSuccess else {
            throw HTTPError.status(code: response.statusCode, body: response.body)
        }
        do {
            return try endpoint.decode(response.body)
        } catch let error as DecodingError {
            throw HTTPError.decoding(path: error.codingPathDescription)
        } catch {
            throw HTTPError.decoding(path: "")
        }
    }

    /// Runs the chain and returns the final response, whatever its status.
    public func execute(_ request: HTTPRequest) async throws -> HTTPResponse {
        let baseURL = baseURL
        let transport = transport
        let send: HTTPNext = { request in
            try await transport.send(Self.urlRequest(for: request, baseURL: baseURL))
        }
        // Fold from the innermost interceptor outwards, so interceptors[0] runs first.
        let chain = interceptors.reversed().reduce(send) { next, interceptor in
            { request in try await interceptor.intercept(request, next: next) }
        }
        return try await chain(request)
    }

    static func urlRequest(for request: HTTPRequest, baseURL: URL) throws -> URLRequest {
        let url = baseURL.appending(path: request.path)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw HTTPError.invalidRequest
        }
        if !request.queryItems.isEmpty {
            components.queryItems = request.queryItems
        }
        guard let finalURL = components.url else { throw HTTPError.invalidRequest }
        // Never read or write the URL cache: responses hold balances and payee details, and
        // Cache.db doesn't get the app's `.complete` file protection (SPEC section 6).
        var urlRequest = URLRequest(url: finalURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        return urlRequest
    }
}

extension HTTPClient {
    /// The standard chain, outermost first (ADR-012):
    ///
    /// 1. Request ID, so every attempt of one call shares an ID the server logs.
    /// 2. Idempotency key, added **outside** retry so every attempt reuses it.
    /// 3. Auth, so a retried attempt after a refresh carries the new token.
    /// 4. Retry with backoff, closest to the network.
    public static func standardInterceptors(auth: AuthInterceptor?, retry: RetryInterceptor = RetryInterceptor())
        -> [any Interceptor]
    {
        var chain: [any Interceptor] = [RequestIDInterceptor(), IdempotencyInterceptor()]
        if let auth { chain.append(auth) }
        chain.append(retry)
        return chain
    }
}

extension DecodingError {
    /// "accounts[0].balance.amountMinor": where decoding failed, without any values.
    var codingPathDescription: String {
        let path: [any CodingKey]
        switch self {
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            path = context.codingPath
        case .keyNotFound(let key, let context):
            path = context.codingPath + [key]
        @unknown default:
            path = []
        }
        return path.reduce(into: "") { result, key in
            if let index = key.intValue {
                result += "[\(index)]"
            } else {
                result += result.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
    }
}
