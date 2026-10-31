import Vapor

/// Turns every thrown error into `{ "code", "message", "requestId" }` (SPEC section 7).
/// Replaces Vapor's `ErrorMiddleware`. Unknown errors become a generic 500, so internal
/// details never reach the client; they are logged with the request ID instead.
struct ErrorEnvelopeMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch {
            let described = Self.describe(error)
            if described.status.code >= 500 {
                request.logger.error("Request failed: \(String(reflecting: type(of: error)))")
            }
            let response = Response(status: described.status)
            try response.content.encode(
                ErrorEnvelope(code: described.code, message: described.message, requestId: request.requestID)
            )
            return response
        }
    }

    static func describe(_ error: any Error) -> APIFailure {
        switch error {
        case let failure as APIFailure:
            return failure
        case is DecodingError:
            return APIFailure.badRequest("The request body is invalid.")
        case let abort as any AbortError where abort.status.code < 500:
            return APIFailure(status: abort.status, code: code(for: abort.status), message: abort.reason)
        default:
            return APIFailure(
                status: .internalServerError,
                code: "internal",
                message: "Something went wrong. Try again."
            )
        }
    }

    private static func code(for status: HTTPResponseStatus) -> String {
        switch status {
        case .notFound: "not_found"
        case .unauthorized: "unauthorized"
        case .methodNotAllowed: "method_not_allowed"
        case .payloadTooLarge: "payload_too_large"
        case .unsupportedMediaType: "unsupported_media_type"
        default: "bad_request"
        }
    }
}
