# ADR-022: Unsigned confirm until Phase 7, and the outbox recovery rule

- **Status:** Proposed
- **Date:** 2026-11-09
- **Related:** SPEC sections 5, 6, 7 and 10, ADR-009, ADR-011, ADR-016

## Context

Phase 6 builds the send flow, but signing (Secure Enclave, nonce, App Attest) is Phase 7. Without a confirm no money moves and the outbox never reaches Completed. The outbox also needs a rule for unknown outcomes: a timeout says nothing about whether the server did the work.

## Decision

`POST /v1/transfers/{id}/confirm` exists from Phase 6 without a signature, and the outbox follows a fixed recovery rule (`TransferRecovery` in Domain).

- **Confirm:** one database transaction of conditional updates claims it (`awaiting_confirmation` → `processing`), debits (`balance = balance - x WHERE balance >= x`) and adds the history row. Other statuses are returned as they are, so repeats are safe. Too little balance, or more than 2 minutes past the quote's expiry, fails it and debits nothing: an old rate isn't a free option. Settlement is 3 s later, on read; `rcp_decline_eur` is declined and refunded.
- **Phase 7** makes the signed payload mandatory on this route. Until then the access token is the only proof, acceptable only on a fake-money sandbox.
- **Recovery:** Authorised → create, Submitted → confirm, Processing → poll; all keyed on the transfer ID. `transfer_exists`/`idempotency_mismatch` → fetch. 404 on confirm → resend the create. A definite refusal fails it with the reason. Anything else waits (2 s doubling to 30 s) and asks again, with no time limit: a timeout is never a failure, and the account history is the backstop.
- New arrow Authorised → Failed: the server can refuse the create.
- Idempotency compares bodies as canonical JSON, so key order doesn't matter. Duplicate keys collapse; keys are per user, so at worst a user replays their own response.

## Alternatives considered

### Option A: Stop at "created" until Phase 7
- Lost: nothing past Submitted could be tested.

### Option B: A stub signature now
- Lost: it looks like a control without being one, and is thrown away in Phase 7.

## Consequences

- **Easier:** the full flow, double tap and kill-resume are testable now.
- **Harder:** until Phase 7 a stolen access token could confirm a transfer (threat model row).
- **Revisit when:** Phase 7 lands and supersedes the unsigned confirm.
