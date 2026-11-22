import Vapor

/// Sandbox fault injection (SPEC section 7) so the app's failure paths can be demoed:
///
/// - `X-Sim-Delay: <ms>` waits before handling (0...30000).
/// - `X-Sim-Fail: server` returns 500 **before** handling: nothing happened.
/// - `X-Sim-Fail: declined` returns 422 `declined` before handling.
/// - `X-Sim-Fail: network` handles the request **then drops the connection** before the
///   response arrives. This is the dangerous case: the transfer exists but the client
///   saw a timeout. Retrying with the same `Idempotency-Key` returns the original result.
struct SimulationMiddleware: AsyncMiddleware {
    static let delayHeader = "X-Sim-Delay"
    static let failHeader = "X-Sim-Fail"
    static let maxDelayMillis = 30_000

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        if let delay = request.headers.first(name: Self.delayHeader) {
            guard let millis = Int(delay), (0...Self.maxDelayMillis).contains(millis) else {
                throw APIFailure.badRequest("\(Self.delayHeader) must be 0...\(Self.maxDelayMillis) milliseconds.")
            }
            try await Task.sleep(for: .milliseconds(millis))
        }

        switch request.headers.first(name: Self.failHeader) {
        case nil:
            return try await next.respond(to: request)
        case "server":
            throw APIFailure(status: .internalServerError, code: "sim_server_error", message: "Simulated server error.")
        case "declined":
            throw APIFailure.declined
        case "network":
            _ = try await next.respond(to: request)
            return Response(
                status: .ok,
                body: Response.Body(asyncStream: { writer in
                    try await writer.write(.error(SimulatedNetworkDrop()))
                })
            )
        default:
            throw APIFailure.badRequest("\(Self.failHeader) must be network, server or declined.")
        }
    }
}

/// Failing the response stream makes the server close the connection mid-response.
struct SimulatedNetworkDrop: Error {}
