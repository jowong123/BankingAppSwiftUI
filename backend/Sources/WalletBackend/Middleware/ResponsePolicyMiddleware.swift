import Vapor

/// Every response is private, per-user money data: no client or proxy may store it.
struct NoStoreMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let response = try await next.respond(to: request)
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
        return response
    }
}

/// One line per request with the route **pattern** (`/v1/transfers/:transferID`), never
/// the concrete path, so account and transfer IDs stay out of the logs. Replaces Vapor's
/// `RouteLoggingMiddleware`. The request ID is already in the logger metadata.
struct AccessLogMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let response = try await next.respond(to: request)
        let pattern = request.route.map { "/" + $0.path.map(\.description).joined(separator: "/") } ?? "unmatched"
        request.logger.info("\(request.method.rawValue) \(pattern) \(response.status.code)")
        return response
    }
}
