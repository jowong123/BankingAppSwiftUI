# ADR-016: Sandbox backend: SQLKit rows, hashed rotating tokens, two-layer idempotency

- **Status:** Accepted
- **Date:** 2026-10-26
- **Related:** SPEC sections 5, 6 and 7, ADR-012, ADR-014

## Context

The Vapor backend in `backend/` is a sandbox with fake money, but it's what the app's retry, refresh and transfer-outbox logic is tested against, and reviewers will read it. Three things needed a decision the spec doesn't make:

1. Fluent `Model` classes must be declared `@unchecked Sendable` under Swift 6, which CLAUDE.md bans without an ADR.
2. Sessions: how tokens are stored, rotated, and what happens when a refresh response is lost.
3. Idempotency: SPEC section 7 says "same `Idempotency-Key` returns the original response", but a lost response, a crash or an expired record must never turn a created transfer into a reported failure (CLAUDE.md, SPEC section 5).

## Decision

**Dependencies.** `vapor`, `fluent`, `fluent-sqlite-driver` and `sql-kit`, all from the Vapor project and used only in `backend/`. Nothing from them reaches the app.

**Persistence.** Fluent configures SQLite and runs migrations. Queries use SQLKit (`sql-kit`, a direct dependency) into plain `Codable, Sendable` row structs. There are no Fluent models and no unchecked Sendable conformances. Money is `Int64` minor units and times are Unix milliseconds in the database.

**Tokens.**
- Access and refresh tokens are 32 random bytes, and only their SHA-256 hashes are stored.
- Access tokens last 15 minutes and refresh tokens 30 days. Each issuance gets a `pairId`.
- Refresh tokens rotate: each one works once, and is claimed atomically with `UPDATE … WHERE revoked = 0 RETURNING`.
- **Reuse** of a rotated refresh token revokes every token for that user. That's theft detection.
- **Grace window:** a rotated token presented again within 30 s is treated as a retry rather than reuse, provided the pair it was rotated into has never been refreshed. The client never got that response. The unused pair is revoked and a new pair issued. If a thief wins the race, the real user's next refresh uses the revoked pair, which counts as reuse and revokes everything.
- The client also never retries a refresh (`allowsRetry = false`, ADR-012).
- Login verifies bcrypt on the thread pool, against a dummy hash for unknown emails, so response time doesn't reveal which accounts exist.

**Idempotency.** There are two layers.
1. *Middleware* (quotes optional, transfers required).
   - Keys are scoped per user. The key is claimed with `INSERT … ON CONFLICT DO NOTHING` and read back. A concurrent duplicate gets 409 `idempotency_in_progress`.
   - A finished request is replayed byte for byte with `Idempotent-Replayed: true`. The same key with a different method, path or body hash gets 422 `idempotency_mismatch`.
   - A thrown error or a 5xx releases the key. That's safe because handlers write in one transaction.
   - Records expire after 24 h. An unfinished claim older than 60 s may be taken over.
2. *Handler.*
   - `POST /v1/transfers` is idempotent on the transfer's own client-generated ID, and the `Idempotency-Key` must equal that ID.
   - An existing transfer with the same details is returned (200) **before** any validation, so a late retry never gets `quote_expired` or `insufficient_funds` for a transfer that exists.
   - The same ID with different details is 409 `transfer_exists`.

**Other.**
- Every response carries `Cache-Control: no-store`.
- Logs show route patterns, not concrete paths with IDs.
- `X-Sim-*` fault injection is off by default and enabled with `SIMULATION_HEADERS=on`. It runs before authentication and can hold a connection for 30 s, so it must never be on by accident.
- On every route, another user's resource is 404 `not_found`, never a different error, so a reply never confirms that someone else's ID exists. That includes creating a transfer with an ID another user already has.

## Alternatives considered

### Option A: Fluent models with `@unchecked Sendable`
- Idiomatic Fluent, less code per query.
- Lost because it needs a standing exception to a hard rule. The type-checker would stop catching data races in the models. Plain SQL is also easier to explain when the interesting part is the locking.

### Option B: JWT access tokens
- Stateless verification, no token table.
- Lost because a sandbox gains nothing from stateless checks, and opaque tokens make revocation (reuse detection, logout) immediate and trivial.

### Option C: Make refresh idempotent by storing the issued tokens
- Replay the exact same token pair for a repeated refresh.
- Lost because it means storing raw tokens (or encrypting them), which defeats hashing at rest. The grace window gets the same user outcome without it.

### Option D: Middleware-only idempotency
- Simpler: trust the 24 h record.
- Lost because the record can be missing even though the transfer exists: it expires, it's released by a 5xx after commit, or a claim crashed. Then a retry would re-validate and fail on an expired quote. Only the transfer ID is permanent.

## Consequences

- **Easier:**
  - A timeout during transfer creation can always be resolved by retrying with the same ID, or by polling `GET /v1/transfers/{id}`.
  - A lost refresh response doesn't log anyone out, provided the old refresh token comes back within the 30 s grace window. The client never retries a refresh, so the next attempt usually comes with the next 401, often later than that. It then counts as reuse and the user signs in again. That fails closed, which is the right side to fail on. Phase 5 can narrow the gap by retrying a refresh that failed in transit as soon as the network returns.
- **Harder:**
  - SQLKit queries are hand-written.
  - Token rows carry rotation bookkeeping (`rotatedAt`, `replacedBy`, `pairId`).
  - The grace window is a 30 s exception to "each refresh token works once" that needs explaining.
- **Known limits (sandbox):**
  - No login rate limiting.
  - Creating a transfer checks the balance but doesn't reserve funds; Phase 7 confirm must re-check and debit atomically.
  - The idempotency store is per-process SQLite.
- **Revisit when:**
  - A real deployment is needed: rate limiting, a shared store (Postgres) for idempotency and tokens, and funds reservation.
