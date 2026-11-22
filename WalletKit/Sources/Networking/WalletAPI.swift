import CryptoKit
import Domain
import Foundation
import NetworkingKit

/// The Wallet API client. The only public entry point of `Networking`: the app builds
/// one in `AppEnvironment` and never imports NetworkingKit itself (ADR-012).
///
/// Every call throws `APIError`. Retry, idempotency keys, request IDs and token refresh
/// happen underneath in NetworkingKit's interceptor chain.
public struct WalletAPI: Sendable {
    private let client: HTTPClient

    /// - Parameter tokens: supplies and refreshes the bearer token (the session store
    ///   from Phase 5).
    ///   - pins: SHA-256 hashes of the server's SubjectPublicKeyInfo, primary and backup
    ///     (ADR-006). Required for an https URL; only a local http backend has none.
    ///
    /// The session is built here, not passed in, so no caller can hand it a shared or
    /// caching session.
    public init(baseURL: URL, tokens: any SessionTokenProvider, pins: Set<Data>) {
        self.init(
            client: HTTPClient(
                baseURL: baseURL,
                transport: Self.transport(baseURL: baseURL, pins: pins),
                interceptors: HTTPClient.standardInterceptors(auth: Self.authInterceptor(tokens: tokens))
            )
        )
    }

    /// Every TLS connection to `baseURL`'s host must present one of `pins`; with none, it
    /// fails closed. A local http backend has no TLS, so there is nothing to pin.
    static func transport(baseURL: URL, pins: Set<Data>) -> URLSessionTransport {
        let pinning = baseURL.host().map { host in
            PinningPolicy(pins: [host: pins]) {
                Data(SHA256.hash(data: $0))
            }
        }
        return URLSessionTransport(session: URLSession(configuration: sessionConfiguration()), pinning: pinning)
    }

    static func authInterceptor(tokens: any SessionTokenProvider) -> AuthInterceptor {
        AuthInterceptor(
            accessToken: {
                await tokens.accessToken()
            },
            refresh: {
                do {
                    return try await tokens.refreshAccessToken()
                } catch {
                    throw Self.refreshFailure(error)
                }
            }
        )
    }

    /// Ephemeral with no URL cache: nothing about the user's money is written to disk
    /// outside the protected SwiftData store (SPEC section 6). No cookies or stored
    /// credentials either: the bearer token is the only credential.
    static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        return configuration
    }

    /// Tells `AuthInterceptor` which refresh failures are a real rejection (lock the
    /// session) and which are just the network (leave the session alone). Only
    /// `SessionRefreshError` and the server's own answers can lock it; any other error
    /// from the session store passes through and the session is kept.
    static func refreshFailure(_ error: any Error) -> any Error {
        switch error {
        case is SessionRefreshError:
            HTTPError.unauthorized
        case APIError.transport(let code):
            HTTPError.transport(code)
        case APIError.cancelled:
            CancellationError()
        case APIError.http(let status), APIError.server(let status, _, _, _):
            HTTPError.status(code: status, body: Data())
        case APIError.unauthorized:
            HTTPError.unauthorized
        // `SessionStore` reports a failed refresh as `AuthError`. Temporary ones keep the
        // session, and become the HTTP errors that tell the user what happened.
        case AuthError.offline:
            HTTPError.transport(.notConnectedToInternet)
        case AuthError.unavailable:
            HTTPError.status(code: 503, body: Data())
        case AuthError.cancelled:
            CancellationError()
        default:
            error
        }
    }

    init(client: HTTPClient) {
        self.client = client
    }

    // MARK: - Accounts

    public func accounts() async throws(APIError) -> [Account] {
        var accounts: [Account] = []
        for dto in try await send(WalletEndpoints.accounts()).accounts {
            accounts.append(try dto.account())
        }
        return accounts
    }

    public func transactions(accountID: String, cursor: String? = nil, limit: Int = 20)
        async throws(APIError) -> TransactionPage
    {
        try await send(WalletEndpoints.transactions(accountID: accountID, cursor: cursor, limit: limit)).page()
    }

    public func recipients() async throws(APIError) -> [Recipient] {
        var recipients: [Recipient] = []
        for dto in try await send(WalletEndpoints.recipients()).recipients {
            recipients.append(try dto.recipient())
        }
        return recipients
    }

    // MARK: - Transfers

    /// The review screen shows this quote and the user signs what it says, so it must be
    /// for exactly what was asked and its numbers must add up (`FXQuote.addsUp`).
    public func createQuote(sourceAmount: Money, targetCurrency: Currency, now: Date = Date()) async throws(APIError)
        -> FXQuote
    {
        let body = QuoteRequestDTO(sourceAmount: try MoneyDTO(sourceAmount), targetCurrency: targetCurrency.code)
        let quote = try await send(WalletEndpoints.createQuote(body)).quote()
        guard quote.sourceAmount == sourceAmount, quote.targetAmount.currency == targetCurrency else {
            throw .invalidResponse("quote does not match request")
        }
        guard quote.addsUp(at: now) else {
            throw .invalidResponse("quote does not add up")
        }
        return quote
    }

    func challenge(transferID: UUID) async throws(APIError) -> SigningChallenge {
        try await send(WalletEndpoints.challenge(id: transferID.uuidString.lowercased())).challenge
    }

    /// `id` is generated by the app before the call and stored in the outbox.
    /// It doubles as the `Idempotency-Key`, so calling this again with the same `id`
    /// returns the original transfer. On `APIError.isOutcomeUnknown`, poll `transfer(id:)`.
    func createTransfer(id: UUID, quoteID: String, recipientID: String, sourceAccountID: String)
        async throws(APIError) -> TransferDTO
    {
        let body = TransferCreateDTO(
            id: id.uuidString.lowercased(),
            quoteId: quoteID,
            recipientId: recipientID,
            sourceAccountId: sourceAccountID
        )
        return try await send(WalletEndpoints.createTransfer(body))
    }

    /// Moves the money. Safe to repeat: the server only changes an unconfirmed transfer.
    func confirmTransfer(id: UUID, confirmation: SignedConfirmation) async throws(APIError) -> TransferDTO {
        try await send(WalletEndpoints.confirmTransfer(id: id.uuidString.lowercased(), confirmation: confirmation))
    }

    func transfer(id: String) async throws(APIError) -> TransferDTO {
        try await send(WalletEndpoints.transfer(id: id))
    }

    // MARK: - Helpers

    private func send<Response>(_ endpoint: Endpoint<Response>) async throws(APIError) -> Response {
        do {
            return try await client.send(endpoint)
        } catch {
            throw APIError.from(error)
        }
    }
}
