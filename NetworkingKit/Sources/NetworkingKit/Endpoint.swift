import Foundation

/// A request plus how to decode its successful response.
///
/// The decoder is a closure rather than a stored `JSONDecoder` so each API can choose its
/// own date and key strategies while `Endpoint` stays `Sendable`.
public struct Endpoint<Response: Sendable>: Sendable {
    public var request: HTTPRequest
    let decode: @Sendable (Data) throws -> Response

    public init(request: HTTPRequest, decode: @escaping @Sendable (Data) throws -> Response) {
        self.request = request
        self.decode = decode
    }
}

extension Endpoint where Response: Decodable {
    public init(request: HTTPRequest, decoder: @escaping @Sendable () -> JSONDecoder = { JSONDecoder() }) {
        self.init(request: request) { data in try decoder().decode(Response.self, from: data) }
    }
}

/// For endpoints whose success response has no body worth decoding.
public struct EmptyResponse: Decodable, Hashable, Sendable {
    public init() {}
}

extension Endpoint where Response == EmptyResponse {
    public init(request: HTTPRequest) {
        self.init(request: request) { _ in EmptyResponse() }
    }
}
