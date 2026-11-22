# ADR-017: No offline cache of account data

- **Status:** Accepted
- **Date:** 2026-11-03
- **Related:** SPEC sections 4, 6 and 10 (Phase 4), ADR-009, ADR-012

## Context

The original Phase 4 plan cached balances and recent transactions in SwiftData so the Accounts screen could show "SGD 12,500.00, updated 5 min ago" without a connection. That is the most sensitive data the app handles after credentials. Once on disk it has to be protected (`.complete` file protection, excluded from backups), wiped on sign-out and session lock, and kept consistent when the server changes it. A cached balance can also be wrong: a user may act on a number that is minutes or days old.

ADR-012 already keeps responses out of `URLCache` for the same reason.

## Decision

AccountsFeature is online only: no balances or transaction history are written to the device.

- `AccountsRepository` (Domain) has one implementation that reads the API (`RemoteAccountsRepository`), and no cache layer.
- With no connection on a cold start, the list shows a full-screen "You're offline" state with Retry, and no numbers.
- Data loaded during this session stays in memory. If a later refresh fails, it stays on screen with a "Couldn't update" banner, and it is gone when the app quits.
- SwiftData is still used, but only for the transfer outbox (Phase 6, ADR-009), which must survive a restart for correctness, not convenience.

## Alternatives considered

### Option A: SwiftData cache of balances
- Balances with a "last updated" time, `.complete` protection.
- Lost because it puts financial data at rest for a convenience feature, adds wipe-on-logout and staleness rules, and a stale balance can mislead.

### Option B: Balances plus the first page of history
- Same as A, with recent transactions offline.
- Lost for the same reasons, with more data to protect: payee names and amounts reveal spending habits.

## Consequences

- **Easier:** nothing to encrypt, wipe or migrate. No stale-data rules. The threat model's data-at-rest row for account data shrinks to "none stored".
- **Harder:** no balances without a connection, which matters to travellers on poor networks.
- **Revisit when:** user research shows people need offline balances. The protocol boundary already allows adding a cache behind `AccountsRepository` without touching the feature.
