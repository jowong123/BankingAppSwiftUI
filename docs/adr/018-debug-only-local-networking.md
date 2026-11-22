# ADR-018: Debug-only ATS exception for the local sandbox backend

- **Status:** Accepted
- **Date:** 2026-11-07
- **Related:** SPEC sections 6 and 7, ADR-006, ADR-012, ADR-016

## Context

From Phase 5 the app talks to the Vapor sandbox backend, which runs on the developer's Mac at `http://127.0.0.1:8080`. App Transport Security blocks plain HTTP, so the simulator can't reach it without either an exception or HTTPS. Weakening a transport control is a security decision (CLAUDE.md), so it needs a record.

## Decision

Debug builds set `NSAllowsLocalNetworking` in `Config/Wallet-Debug.plist`; Release builds have no ATS exception at all.

- The exception covers local addresses only (loopback, `.local`, unqualified names). Every other host still needs HTTPS with ATS's TLS rules.
- The backend URL is `WalletAPIBaseURL` in the same per-configuration plist. Release points at `https://api.wallet.invalid` until a backend is deployed (Phase 9); `.invalid` can never resolve, so a Release build fails closed.
- A missing or malformed URL makes the app use `UnconfiguredAuthAPI` and `UnconfiguredAccountsRepository`, which report "unavailable" rather than guessing a server.
- `WalletTests` asserts the Debug plist has `NSAllowsLocalNetworking` and not `NSAllowsArbitraryLoads`. The Release Info.plist was checked by hand: no `NSAppTransportSecurity` key.
- TLS pinning (Phase 7, ADR-006) applies to the real host and is unaffected.

## Alternatives considered

### Option A: HTTPS locally with a self-signed certificate
- Run Vapor with TLS and trust its certificate on each simulator.
- Lost because every developer machine and CI runner needs certificate setup, and a trusted local CA on the simulator is itself a weaker control than a scoped, Debug-only exception.

### Option B: `NSAllowsArbitraryLoads` or an exception domain in all builds
- One plist for every configuration.
- Lost because it ships an exception in Release. A shipped banking app must have none.

## Consequences

- **Easier:** `swift run WalletBackend serve`, then run the app; nothing to install.
- **Harder:** two plists to keep in step (`WalletAPIBaseURL`, Face ID text lives in build settings).
- **Revisit when:** the backend is deployed (Phase 9): Release gets the real HTTPS URL, and Debug may switch to a deployed sandbox, removing the exception.
