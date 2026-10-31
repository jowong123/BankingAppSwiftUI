import Vapor

/// An error the API reports with a stable `code` (SPEC section 7 error envelope).
/// Clients branch on `code`; `message` is for humans and may change.
struct APIFailure: AbortError, Equatable {
    let status: HTTPResponseStatus
    let code: String
    let message: String

    var reason: String { message }

    static let unauthorized = APIFailure(status: .unauthorized, code: "unauthorized", message: "Sign in again.")
    static let invalidCredentials = APIFailure(
        status: .unauthorized,
        code: "invalid_credentials",
        message: "Email or password is incorrect."
    )
    static let invalidRefreshToken = APIFailure(
        status: .unauthorized,
        code: "invalid_refresh_token",
        message: "Session expired. Sign in again."
    )
    static let notFound = APIFailure(status: .notFound, code: "not_found", message: "Not found.")
    static let idempotencyKeyRequired = APIFailure(
        status: .badRequest,
        code: "idempotency_key_required",
        message: "This request needs an Idempotency-Key header."
    )
    static let idempotencyMismatch = APIFailure(
        status: .unprocessableEntity,
        code: "idempotency_mismatch",
        message: "This Idempotency-Key was already used with a different request."
    )
    static let idempotencyInProgress = APIFailure(
        status: .conflict,
        code: "idempotency_in_progress",
        message: "A request with this Idempotency-Key is still being processed."
    )
    static let quoteExpired = APIFailure(
        status: .unprocessableEntity,
        code: "quote_expired",
        message: "The rate has changed. Get a new quote."
    )
    static let quoteUsed = APIFailure(
        status: .conflict,
        code: "quote_used",
        message: "This quote has already been used for a transfer."
    )
    static let insufficientFunds = APIFailure(
        status: .unprocessableEntity,
        code: "insufficient_funds",
        message: "Not enough balance in this account."
    )
    static let declined = APIFailure(
        status: .unprocessableEntity,
        code: "declined",
        message: "The transfer was declined."
    )

    static func invalid(_ message: String) -> APIFailure {
        APIFailure(status: .unprocessableEntity, code: "invalid_request", message: message)
    }

    static func badRequest(_ message: String) -> APIFailure {
        APIFailure(status: .badRequest, code: "bad_request", message: message)
    }
}

/// `{ "code", "message", "requestId" }`, the body of every non-2xx response.
struct ErrorEnvelope: Content {
    let code: String
    let message: String
    let requestId: String
}
