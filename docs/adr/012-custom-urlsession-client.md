# ADR-012: Custom URLSession client with interceptors, in a standalone NetworkingKit package

- **Status:** Accepted
- **Date:** 2026-10-26
- **Related:** SPEC sections 3, 6 and 7, ADR-004, ADR-006, ADR-014, ADR-016

## Context

Every call to the Wallet API needs the same cross-cutting behaviour: a request ID, an `Idempotency-Key` on mutating calls, retry with backoff, and a bearer token with one refresh on 401 (SPEC section 6). A retried POST must reuse its idempotency key, or a timeout can turn into a double transfer. Phase 7 adds TLS public-key pinning (ADR-006), which needs a `URLSessionDelegate` we control.

None of that HTTP machinery knows anything about wallets, money or transfers. If it lives in `Networking` next to the Wallet endpoints, the two blur together and the generic part can't be tested or reused on its own.

## Decision

The HTTP client is our own thin layer over `URLSession`, in a separate local package `NetworkingKit/` that imports Foundation only. WalletKit's `Networking` target depends on it and contains only the Wallet API: endpoints, DTOs and the mapping to Domain types.

- `HTTPClient` runs each request through an ordered chain of `Interceptor`s and then an `HTTPTransport`. The transport is injected, so interceptor tests use a recording stub and `URLSessionTransport` is tested against a `URLProtocol` stub.
- Chain order, outermost first: `RequestIDInterceptor` → `IdempotencyInterceptor` → `AuthInterceptor` → `RetryInterceptor` → transport. Idempotency sits outside retry, so every attempt carries the same key.
- `RetryInterceptor` retries transient transport errors (an allow-list: offline, timeout, connection lost, DNS), 5xx and 429 only: 3 attempts, 0.5 s base, exponential with full jitter. A POST is retried only if it carries an `Idempotency-Key`. TLS, certificate, ATS and bad-URL errors are never retried, so a Phase 7 pinning failure surfaces at once. A request marked `allowsRetry = false` is never retried. Token refresh is marked that way, because the server rotates refresh tokens and a resend would look like theft (ADR-016).
- `AuthInterceptor` is an actor. On 401 it refreshes once (concurrent 401s share one refresh), retries once, then throws `unauthorized`. Only a definite rejection of the refresh locks the session: a 400, 401 or 403 from the server, or a `SessionRefreshError` from the session store (no refresh token stored, or refused). Offline, timeout, 408, 429, 5xx and any other session-store error (such as the Keychain being unavailable while the device is locked) are rethrown unchanged, so losing signal or being rate limited never logs the user out.
- Every request ignores the URL cache, and `WalletAPI` builds its own ephemeral session with no cache or cookies. Balances must not land in `Cache.db`, which lacks `.complete` protection. The session also has no credential storage. Callers can't pass in a session, so they can't bypass the Phase 7 pinning delegate.
- `URLSessionTransport` never follows redirects; the 3xx is returned as the response. URLSession drops `Authorization` on a cross-host redirect, but it resends the request body, and for login and refresh that body holds the password or the refresh token. Redirects are refused by a per-task delegate, so the session delegate stays free for pinning.
- `HTTPRequest` and the token DTOs redact themselves in `description`, `debugDescription` and `Mirror`, so logs, `dump` and test failures never show tokens or passwords.
- Outcome classification lives in `Networking`'s `APIError`. `isDefiniteRejection` is an allow-list of server error codes. Everything else (timeouts, 5xx, cancellation, an undecodable 2xx, 409 in progress) counts as `isOutcomeUnknown`, which means poll the transfer, never mark it failed.
- NetworkingKit has no logging and no knowledge of WalletKit. A logging interceptor will live in `Networking`, which can import `Observability`, once Observability gains its `Logger` (Phase 9). Until then nothing logs requests.
- Only `Networking` may import NetworkingKit. The app target builds the client through `Networking`'s `WalletAPI`, so it never imports NetworkingKit either. The boundary script checks both.

ADR-004 rejected a package per module. This package is different: it is one generic library with no WalletKit dependency, not an app module, so the extra manifest also shows that it builds alone.

## Alternatives considered

### Option A: Alamofire
- Mature, with interceptors (`RequestInterceptor`) and retry policies built in.
- Lost because it's a third-party dependency in the most security-sensitive path, it predates Swift 6 strict concurrency, and the parts we need are about 300 lines on top of `URLSession`. Interviewers at DBS and Thales will also ask how retry and idempotency work, and owning the code answers that.

### Option B: NetworkingKit as a target inside WalletKit
- Same code as another target in `WalletKit/Package.swift`, like `IdentitySDK`.
- Lost because "generic, builds alone" would only be a convention for anyone reading the package. A separate package makes the compiler enforce it and lets CI test it in isolation.

## Consequences

- **Easier:** retry, idempotency and refresh logic are tested without any Wallet types. Pinning in phase 7 plugs into the session delegate we already own.
- **Harder:** one more package to keep in CI, swift-format and the boundary script. We maintain the HTTP layer ourselves.
- **Revisit when:** we need HTTP/3 tuning, multipart uploads or background transfers beyond what a thin `URLSession` wrapper does cleanly, or a second app wants to share the package (publish it as a versioned package).
