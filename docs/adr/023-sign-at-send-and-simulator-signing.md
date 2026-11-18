# ADR-023: Sign at Send, and how the simulator signs

- **Status:** Accepted
- **Date:** 2026-11-14
- **Related:** SPEC section 6, ADR-008, ADR-009, ADR-022, ADR-024

## Context

SPEC section 6 lists the signing steps but not when they run. The outbox (ADR-009) sends in the background and resumes after a crash, when nobody is looking at the screen, and a nonce lasts 60 s. Separately, the simulator has no Secure Enclave and no App Attest, yet development and the end-to-end test run there.

## Decision

Face ID signs when the user taps Send, before the outbox sees the transfer; the simulator uses a key it generates itself, and the server accepts unattested devices only when started with `ATTEST_MODE=sandbox`.

- **At Send:** challenge for the app's own transfer ID (before the create), Face ID, sign, then save to the outbox with the signed approval. Every confirm, also after a relaunch, sends that approval unchanged. The outbox never prompts.
- **Expiry:** an approval the server gets more than 60 s after the challenge is refused as `nonce_expired`; the transfer fails as "approval expired" and nothing moves.
- **Simulator:** `SoftwareKey`, wired only under `#if targetEnvironment(simulator)`. A random P-256 key generated at sign-in, kept in the Keychain (`WhenUnlockedThisDeviceOnly`), signing only after a Face ID prompt (the simulator's Features > Face ID menu), and refusing once the enrolment changes. Never a fixed key in source.
- **Server:** `ATTEST_MODE=sandbox` skips App Attest only; the signature, nonce and payload checks are the same. Without it, `APP_ATTEST_APP_ID` is required or the server won't start.

## Alternatives considered

### Option A: Sign when the outbox reaches confirm
- Lost: after a crash the prompt has no screen to explain it.

### Option B: A fixed demo key in the app and backend
- Lost: anyone who reads the repo can sign; breaks "no secrets in source".

### Option C: Device only
- Lost: no simulator or CI path to try the signed flow end to end.

## Consequences

- **Easier:** one prompt, while the user is looking; the outbox stays prompt-free.
- **Harder:** more than 60 s offline after Send fails the transfer; the simulator key is weaker than the Secure Enclave (fake money, simulator only).
- **Revisit when:** Phase 9 adds a release pipeline (check no simulator path ships), or long offline periods become a real use case.
