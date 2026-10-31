import Foundation

/// Adds `Authorization: Bearer <token>` and handles 401 with one refresh and one retry.
///
/// - If the retry is also 401, or the server definitely rejects the refresh (400, 401 or
///   403, or `HTTPError.unauthorized` from `refresh`), it throws `HTTPError.unauthorized`
///   and the app locks the session (SPEC section 6). It never loops.
/// - Any other refresh failure (offline, timeout, 408, 429, 5xx) is rethrown unchanged:
///   being offline or rate limited must not log the user out.
/// - An actor so concurrent 401s share one refresh: the first starts it, the others
///   await the same task. Refresh tokens rotate, so two parallel refreshes would make
///   the server reject the second and log the user out.
/// - Requests with `requiresAuthentication == false` (login, refresh) pass straight through.
public actor AuthInterceptor: Interceptor {
    public typealias TokenSource = @Sendable () async -> String?
    public typealias Refresh = @Sendable () async throws -> String

    private let accessToken: TokenSource
    private let refresh: Refresh
    private var refreshTask: Task<String, any Error>?

    /// - Parameters:
    ///   - accessToken: the current token, or `nil` when there is no session.
    ///   - refresh: gets and stores a new access token, returning it. Throws if it can't.
    public init(accessToken: @escaping TokenSource, refresh: @escaping Refresh) {
        self.accessToken = accessToken
        self.refresh = refresh
    }

    public func intercept(_ request: HTTPRequest, next: HTTPNext) async throws -> HTTPResponse {
        guard request.requiresAuthentication else { return try await next(request) }

        let token = await accessToken()
        let response = try await next(Self.authorized(request, token: token))
        guard response.statusCode == 401 else { return response }

        let newToken: String
        do {
            newToken = try await refreshedToken(replacing: token)
        } catch let error as HTTPError where Self.isDefiniteRejection(error) {
            throw HTTPError.unauthorized
        }
        let retried = try await next(Self.authorized(request, token: newToken))
        guard retried.statusCode != 401 else { throw HTTPError.unauthorized }
        return retried
    }

    private func refreshedToken(replacing stale: String?) async throws -> String {
        if let refreshTask {
            return try await refreshTask.value
        }
        // Another request may have finished a refresh while this one was in flight.
        if let current = await accessToken(), current != stale {
            return current
        }
        // A refresh may have started during the await above.
        if let refreshTask {
            return try await refreshTask.value
        }
        // Unstructured on purpose: other requests await this same task, so cancelling the
        // caller that started it must not cancel the refresh they are all waiting on.
        let task = Task { [refresh] in try await refresh() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    /// Statuses where the server looked at the refresh token and refused it. Not every
    /// 4xx: 408 (timeout) and 429 (rate limited) say nothing about the token.
    static let rejectingStatuses: Set<Int> = [400, 401, 403]

    static func isDefiniteRejection(_ error: HTTPError) -> Bool {
        switch error {
        case .unauthorized: true
        case .status(let code, _): rejectingStatuses.contains(code)
        default: false
        }
    }

    private static func authorized(_ request: HTTPRequest, token: String?) -> HTTPRequest {
        guard let token else { return request }
        var request = request
        request.setHeader(HTTPHeader.authorization, "Bearer \(token)")
        return request
    }
}
