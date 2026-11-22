import Domain
import Foundation
import NetworkingKit

/// Login and token refresh against the Wallet API. `SessionStore` uses it through the
/// Domain `AuthAPI` protocol.
///
/// It has its own client with no `AuthInterceptor`: these two calls never send a bearer
/// token, and `WalletAPI` needs the session store for its tokens while the session store
/// needs this to get them. Two clients break that cycle.
public struct RemoteAuthAPI: AuthAPI {
    private let client: HTTPClient

    /// - Parameter pins: the same pins as `WalletAPI` (ADR-006).
    public init(baseURL: URL, pins: Set<Data>) {
        self.init(
            client: HTTPClient(
                baseURL: baseURL,
                transport: WalletAPI.transport(baseURL: baseURL, pins: pins),
                interceptors: HTTPClient.standardInterceptors(auth: nil)
            )
        )
    }

    init(client: HTTPClient) {
        self.client = client
    }

    public func login(email: String, password: String) async throws(AuthError) -> BindingToken {
        do {
            let dto = try await client.send(WalletEndpoints.login(email: email, password: password))
            return BindingToken(dto.bindingToken)
        } catch {
            throw Self.loginError(APIError.from(error))
        }
    }

    public func bindDevice(_ request: DeviceBindingRequest) async throws(AuthError) -> BoundSession {
        do {
            return try await client.send(WalletEndpoints.bindDevice(request)).session()
        } catch {
            throw Self.bindingError(APIError.from(error))
        }
    }

    public func refresh(refreshToken: String) async throws(AuthError) -> SessionTokens {
        do {
            let dto = try await client.send(WalletEndpoints.refresh(refreshToken: refreshToken))
            return dto.tokens()
        } catch {
            throw Self.refreshError(APIError.from(error))
        }
    }

    public func logout(refreshToken: String) async throws(AuthError) {
        do {
            _ = try await client.send(WalletEndpoints.logout(refreshToken: refreshToken))
        } catch {
            throw Self.common(APIError.from(error))
        }
    }

    /// A 401 on login is a wrong email or password, never an expired session.
    static func loginError(_ error: APIError) -> AuthError {
        switch error {
        case .server(401, _, _, _), .http(401):
            .invalidCredentials
        default:
            common(error)
        }
    }

    /// Any refusal of the device (a used or expired binding token, a refused key or
    /// attestation) means starting the sign-in over.
    static func bindingError(_ error: APIError) -> AuthError {
        switch error {
        case .server(let status, _, _, _) where (400..<500).contains(status):
            .deviceSetupFailed
        case .http(let status) where (400..<500).contains(status):
            .deviceSetupFailed
        default:
            common(error)
        }
    }

    /// Only a definite refusal of the refresh token ends the session: 400, 401 or 403,
    /// the same rule as `AuthInterceptor`. Anything else (offline, 5xx, 429) is temporary.
    static func refreshError(_ error: APIError) -> AuthError {
        switch error {
        case .server(400, _, _, _), .server(401, _, _, _), .server(403, _, _, _), .http(400), .http(401), .http(403):
            .sessionExpired
        default:
            common(error)
        }
    }

    private static func common(_ error: APIError) -> AuthError {
        switch error {
        case .transport where error.isOffline:
            .offline
        // Refused, no such host, or TLS refused: the server can't be reached, so "check your
        // connection" would be wrong. Covers a stopped backend and a misconfigured build.
        case .transport:
            .unavailable
        case .pinningFailed:
            .unavailable
        case .cancelled:
            .cancelled
        default:
            .unavailable
        }
    }
}

extension SessionTokensDTO {
    func tokens() -> SessionTokens {
        SessionTokens(accessToken: accessToken, refreshToken: refreshToken)
    }
}
