import Domain

/// `AccountsRepository` over the Wallet API: the only way AccountsFeature reaches the
/// network (ADR-004). It turns `APIError` into `DataSourceError`, so features never see
/// HTTP details. `WalletAPI` keeps the full `APIError` for flows that need it (transfers).
public struct RemoteAccountsRepository: AccountsRepository {
    private let api: WalletAPI

    public init(api: WalletAPI) {
        self.api = api
    }

    public func accounts() async throws(DataSourceError) -> [Account] {
        do {
            return try await api.accounts()
        } catch {
            throw error.dataSourceError
        }
    }

    public func transactions(accountID: String, cursor: String?) async throws(DataSourceError) -> TransactionPage {
        do {
            return try await api.transactions(accountID: accountID, cursor: cursor)
        } catch {
            throw error.dataSourceError
        }
    }
}

extension APIError {
    /// What a read failure means for the user. Only for reads: a failed transfer needs
    /// `isOutcomeUnknown`, which this deliberately throws away.
    var dataSourceError: DataSourceError {
        switch self {
        case .transport:
            .offline
        case .unauthorized:
            .sessionExpired
        case .cancelled:
            .cancelled
        case .server(let status, _, _, _), .http(let status):
            Self.isTemporary(status: status) ? .unavailable : .invalidData
        case .invalidResponse, .invalidRequest:
            .invalidData
        }
    }

    /// Statuses where trying again later can work: server errors, timeouts, rate limits.
    private static func isTemporary(status: Int) -> Bool {
        status >= 500 || status == 408 || status == 429
    }
}
