# ADR-009: SwiftData outbox with `.complete` file protection

- **Status:** Proposed
- **Date:** 2026-11-09
- **Related:** SPEC sections 2, 4, 5 and 6, ADR-011, ADR-017, ADR-022

## Context

A transfer must survive a kill between Send and the server's answer, never lost or doubled (SPEC section 5), so its state is saved before each network call. That state is financial data (amount, rate, payee name). ADR-017 keeps balances off the device; the outbox is the one exception and must be protected accordingly.

## Decision

The `TransferOutbox` actor in Persistence stores transfers with SwiftData, in its own folder with `.complete` file protection, excluded from backups.

- `OutboxStore` is a `@ModelActor`, so the non-Sendable `ModelContext` stays on its executor; only `Transfer` values cross it. `TransferOutbox` holds the logic and no SwiftData types.
- `TransferRecord` uses flat columns, so a Domain change can't silently change what's stored. It keeps the payee's name and last four digits; no tokens.
- The folder gets `.complete` before the store is created; the database and journal files inherit it. A write that fails while locked stops that transfer's task, and it resumes when the app becomes active.
- The store opens on first use (a launch can happen while locked) and retries a failed open; until then nothing is sent and "pending?" answers yes. Finished transfers are deleted on resume.
- Reaching the sign-in screen by any path deletes the store's files (not just rows), retrying a failed delete before reuse, and stops new sends until a session resumes. A Submitted or Processing transfer may already be debited; its outcome then shows only in the account history. Accepted: otherwise payee data outlives the session.

## Alternatives considered

### Option A: GRDB with SQLCipher
- Encrypted SQLite with a key in the Keychain.
- Lost: two dependencies, and the key would sit behind the same device lock that `.complete` already uses.

### Option B: One JSON file per transfer, or the Keychain
- `Codable` files with `.completeFileProtection`, or Keychain items.
- Lost: queries, atomic updates and migrations would be hand-written; the Keychain is for secrets, not changing records.

## Consequences

- **Easier:** crash-safe sends with little code; in-memory tests.
- **Harder:** nothing resumes while the phone is locked. The simulator has no data protection, so that check runs on a device.
- **Revisit when:** transfers must finish while locked (`.completeUntilFirstUserAuthentication` plus a threat-model row), or migrations get painful.
