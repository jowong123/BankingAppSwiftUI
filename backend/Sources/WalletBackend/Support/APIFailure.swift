import Vapor

/// An error the API reports with a stable `code` (SPEC section 7 error envelope).
/// Clients branch on `code`; `message` is for humans and may change.
struct APIFailure: AbortError, Equatable {
    let status: HTTPResponseStatus
    let code: String
    let message: String

    var reason: String {
        message
    }

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

    // MARK: Device binding and signing

    static let invalidBindingToken = APIFailure(
        status: .unauthorized,
        code: "invalid_binding_token",
        message: "Sign in again to set up this device."
    )
    static let attestationInvalid = APIFailure(
        status: .unprocessableEntity,
        code: "attestation_invalid",
        message: "This device couldn't be verified."
    )
    /// The session's device has no signing key, or the session predates device binding.
    static let deviceNotBound = APIFailure(
        status: .forbidden,
        code: "device_not_bound",
        message: "Set up Face ID and sign in again to send money."
    )
    static let signatureRequired = APIFailure(
        status: .unprocessableEntity,
        code: "signature_required",
        message: "This confirm must be signed."
    )
    static let invalidSignature = APIFailure(
        status: .unprocessableEntity,
        code: "invalid_signature",
        message: "The signature doesn't match this device."
    )
    static let payloadMismatch = APIFailure(
        status: .unprocessableEntity,
        code: "payload_mismatch",
        message: "What was signed doesn't match this transfer."
    )
    static let invalidNonce = APIFailure(
        status: .unprocessableEntity,
        code: "invalid_nonce",
        message: "This approval wasn't issued for this transfer."
    )
    static let nonceUsed = APIFailure(
        status: .unprocessableEntity,
        code: "nonce_used",
        message: "This approval was already used."
    )
    static let nonceExpired = APIFailure(
        status: .unprocessableEntity,
        code: "nonce_expired",
        message: "The approval expired. Nothing was sent."
    )
    static let assertionInvalid = APIFailure(
        status: .unprocessableEntity,
        code: "assertion_invalid",
        message: "This request didn't come from a verified app."
    )

    static let tooManyChallenges = APIFailure(
        status: .tooManyRequests,
        code: "too_many_requests",
        message: "Too many approvals asked for this transfer. Try again in a minute."
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
