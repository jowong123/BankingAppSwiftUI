import Foundation
import NetworkingKit

/// The Wallet API routes (SPEC section 7, `backend/openapi.yaml`). Device binding and
/// signing routes arrive in Phase 7.
enum WalletEndpoints {
    static func login(email: String, password: String) throws(APIError) -> Endpoint<SessionTokensDTO> {
        try post(
            "/v1/auth/login", body: LoginRequestDTO(email: email, password: password), requiresAuthentication: false)
    }

    /// Never retried: the server rotates refresh tokens, so resending one whose response
    /// was lost would look like a stolen token (ADR-012, ADR-016).
    static func refresh(refreshToken: String) throws(APIError) -> Endpoint<SessionTokensDTO> {
        var endpoint: Endpoint<SessionTokensDTO> = try post(
            "/v1/auth/refresh",
            body: RefreshRequestDTO(refreshToken: refreshToken),
            requiresAuthentication: false
        )
        endpoint.request.allowsRetry = false
        return endpoint
    }

    static func accounts() -> Endpoint<AccountsResponseDTO> {
        get("/v1/accounts")
    }

    static func transactions(accountID: String, cursor: String?, limit: Int) throws(APIError)
        -> Endpoint<TransactionPageDTO>
    {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        return get("/v1/accounts/\(try pathID(accountID))/transactions", query: query)
    }

    static func recipients() -> Endpoint<RecipientsResponseDTO> {
        get("/v1/recipients")
    }

    static func createQuote(_ body: QuoteRequestDTO) throws(APIError) -> Endpoint<QuoteDTO> {
        try post("/v1/quotes", body: body)
    }

    /// The transfer's client-generated ID is also its `Idempotency-Key` (SPEC section 5),
    /// so a retry after an app restart still can't create a second transfer.
    static func createTransfer(_ body: TransferCreateDTO) throws(APIError) -> Endpoint<TransferDTO> {
        var endpoint: Endpoint<TransferDTO> = try post("/v1/transfers", body: body)
        endpoint.request.setHeader(HTTPHeader.idempotencyKey, body.id)
        return endpoint
    }

    static func transfer(id: String) throws(APIError) -> Endpoint<TransferDTO> {
        get("/v1/transfers/\(try pathID(id))")
    }

    // MARK: - Helpers

    private static func get<Response: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = [])
        -> Endpoint<Response>
    {
        Endpoint(
            request: HTTPRequest(method: .get, path: path, queryItems: query, headers: jsonHeaders),
            decoder: WalletJSON.decoder
        )
    }

    private static func post<Body: Encodable, Response: Decodable & Sendable>(
        _ path: String,
        body: Body,
        requiresAuthentication: Bool = true
    ) throws(APIError) -> Endpoint<Response> {
        let data: Data
        do {
            data = try WalletJSON.encoder().encode(body)
        } catch {
            throw .invalidRequest
        }
        var headers = jsonHeaders
        headers[HTTPHeader.contentType] = "application/json"
        return Endpoint(
            request: HTTPRequest(
                method: .post,
                path: path,
                headers: headers,
                body: data,
                requiresAuthentication: requiresAuthentication
            ),
            decoder: WalletJSON.decoder
        )
    }

    private static let jsonHeaders = [HTTPHeader.accept: "application/json"]

    /// IDs go into URL paths, so only allow characters that can't change the path:
    /// an ID like "../admin" or "a/b" is rejected rather than escaped.
    static func pathID(_ id: String) throws(APIError) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard !id.isEmpty, id.count <= 128, id.unicodeScalars.allSatisfy(allowed.contains) else {
            throw .invalidRequest
        }
        return id
    }
}
