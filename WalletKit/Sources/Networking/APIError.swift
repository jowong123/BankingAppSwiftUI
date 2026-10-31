import Foundation
import NetworkingKit

/// Every way a Wallet API call can fail. View models map these to `UserFacingError`.
public enum APIError: Error, Hashable, Sendable {
    /// The server's error envelope: `{ "code", "message", "requestId" }` (SPEC section 7).
    case server(status: Int, code: String, message: String, requestID: String?)
    /// A non-2xx response without a readable error envelope.
    case http(status: Int)
    /// 401 that a token refresh couldn't fix. The session must lock (SPEC section 6).
    case unauthorized
    /// No response arrived. For a mutating call the outcome is unknown: never mark a
    /// transfer failed on this; poll its status first (SPEC section 5).
    case transport(URLError.Code)
    /// The response didn't match the contract. Holds a coding path or field name, never values.
    case invalidResponse(String)
    /// The call couldn't be built, e.g. an ID with characters not allowed in a path.
    case invalidRequest
    case cancelled

    /// Server error codes that mean "this request was rejected and changed nothing".
    /// Anything not on this list might have been applied (SPEC section 7, `openapi.yaml`).
    static let definiteRejectionCodes: Set<String> = [
        "bad_request", "invalid_request", "not_found", "declined",
        "quote_expired", "quote_used", "insufficient_funds",
        "idempotency_key_required", "idempotency_mismatch",
    ]

    /// `true` only when the server explicitly rejected the call, or it never left the
    /// device. Then nothing happened and the user can safely change it and try again.
    public var isDefiniteRejection: Bool {
        switch self {
        case .server(let status, let code, _, _):
            (400..<500).contains(status) && Self.definiteRejectionCodes.contains(code)
        case .invalidRequest:
            true
        default:
            false
        }
    }

    /// `true` when the server may or may not have done the work: a timeout, a 5xx, a
    /// cancelled call, a 2xx that didn't decode, a 401 after an earlier attempt, a 409
    /// "in progress". Deliberately the complement of `isDefiniteRejection`, so a new error
    /// shape defaults to "check status", never to "failed". For a transfer this means
    /// poll `transfer(id:)`; it is never shown as failed (CLAUDE.md, SPEC section 5).
    public var isOutcomeUnknown: Bool { !isDefiniteRejection }
}

extension APIError {
    /// Turns anything thrown below `WalletAPI` into an `APIError`.
    static func from(_ error: any Error) -> APIError {
        switch error {
        case let error as APIError:
            return error
        case is CancellationError:
            return .cancelled
        case let error as HTTPError:
            return from(error)
        default:
            return .invalidResponse("unexpected")
        }
    }

    private static func from(_ error: HTTPError) -> APIError {
        switch error {
        case .transport(let code):
            return .transport(code)
        case .unauthorized:
            return .unauthorized
        case .decoding(let path):
            return .invalidResponse(path)
        case .invalidRequest:
            return .invalidRequest
        case .invalidResponse:
            return .invalidResponse("not HTTP")
        case .status(let status, let body):
            guard let envelope = try? WalletJSON.decoder().decode(ErrorEnvelopeDTO.self, from: body) else {
                return .http(status: status)
            }
            return .server(
                status: status,
                code: envelope.code,
                message: envelope.message,
                requestID: envelope.requestId
            )
        }
    }
}
