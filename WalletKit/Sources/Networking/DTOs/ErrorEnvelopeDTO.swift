import Foundation

/// `{ "code", "message", "requestId" }`, the body of every non-2xx response.
struct ErrorEnvelopeDTO: Decodable {
    let code: String
    let message: String
    let requestId: String?
}
