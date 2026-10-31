import Vapor

/// Echoes the client's `X-Request-ID`, or makes one, and puts it on every response.
/// A client-sent ID is only trusted if it's short and plain, so it can't inject into logs.
struct RequestIDMiddleware: AsyncMiddleware {
    static let header = "X-Request-ID"

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let incoming = request.headers.first(name: Self.header)
        let id = incoming.flatMap(Self.validated) ?? UUID().uuidString.lowercased()
        request.storage[RequestIDKey.self] = id
        request.logger[metadataKey: "request-id"] = .string(id)

        let response = try await next.respond(to: request)
        response.headers.replaceOrAdd(name: Self.header, value: id)
        return response
    }

    static func validated(_ id: String) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard (1...128).contains(id.count), id.unicodeScalars.allSatisfy({ $0.isASCII && allowed.contains($0) })
        else { return nil }
        return id
    }
}

private struct RequestIDKey: StorageKey {
    typealias Value = String
}

extension Request {
    /// Set by `RequestIDMiddleware`, which runs first.
    var requestID: String { storage[RequestIDKey.self] ?? "unknown" }
}
