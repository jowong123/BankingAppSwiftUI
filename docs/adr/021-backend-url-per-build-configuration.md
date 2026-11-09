# ADR-021: Backend URL set per build configuration in Info.plist

- **Status:** Proposed
- **Date:** 2026-11-08
- **Related:** SPEC sections 2 and 7, ADR-005, ADR-018

## Context

From Phase 5 the app talks to a real server: the local Vapor sandbox at `http://127.0.0.1:8080` in development, and a deployed HTTPS host later (Phase 9). The Debug server address must never reach a Release build, and a build with no server configured must fail safely rather than guess one. ADR-018 covers the matching ATS exception; this record covers where the address itself lives and how it reaches the code.

## Decision

The base URL is the `WalletAPIBaseURL` key in a per-configuration Info.plist, read once by `AppEnvironment` and passed into the API clients.

- The app target's `INFOPLIST_FILE` is `Config/Wallet-Debug.plist` for Debug (`http://127.0.0.1:8080`) and `Config/Wallet-Release.plist` for Release (`https://api.wallet.invalid` until Phase 9). `.invalid` can never resolve.
- `AppEnvironment.baseURL(from:)` reads `Bundle.main.infoDictionary` and accepts only a URL with a host.
- The URL goes to `RemoteAuthAPI(baseURL:)` and `WalletAPI(baseURL:tokens:)`, and on into each one's `HTTPClient`. Endpoints add only their paths (`/v1/auth/login`). No other code knows the server address.
- A missing or malformed value builds `UnconfiguredAuthAPI` and `UnconfiguredAccountsRepository`, which report "unavailable" for every call.
- `WalletTests` checks the parser and the Debug value. The Release build was checked by hand for no local address.

## Alternatives considered

### Option A: A constant in Swift behind `#if DEBUG`
- `let baseURL = URL(string: "http://127.0.0.1:8080")!` in `Networking`.
- Lost because it needs a force unwrap or extra handling, puts the address inside a module that should be server-agnostic, and needs a code change for each new environment.

### Option B: An `.xcconfig` variable substituted into a single plist
- `WALLET_API_BASE_URL` per configuration, written into the plist as `$(WALLET_API_BASE_URL)`.
- Lost for now because `//` in an xcconfig starts a comment, so URLs need escaping. The ATS keys would also still need per-configuration plists. It's worth reconsidering if a third environment appears.

## Consequences

- **Easier:** changing servers is a plist edit. The Debug address and ATS exception live in one file. Tests can pass any `info` dictionary into `AppEnvironment.live(arguments:info:)`.
- **Harder:** two plists to keep in step. The URL is visible in the shipped bundle, which is fine because it isn't secret.
- **Revisit when:** a staging environment or deployed sandbox is added in Phase 9, which may justify xcconfig files or one scheme per environment.
