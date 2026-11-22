import Foundation

/// Sends one fully built request and returns the raw response, whatever its status.
/// The seam between the interceptor chain and the network, so tests can replace it.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}
