# ADR-008: Secure Enclave transaction signing with `.biometryCurrentSet`

- **Status:** Accepted
- **Date:** 2026-11-14
- **Related:** SPEC section 6, ADR-019, ADR-022, ADR-023

## Context

Until Phase 7 a bearer token was enough to confirm a transfer (ADR-022). A stolen token, a malicious proxy or a compromised server path could move money the user never saw. Approval must prove three things: this device, this person, and exactly these numbers.

## Decision

Every confirm carries a payload signed by a P-256 key that lives in the Secure Enclave and only signs after Face ID or Touch ID, and the server verifies it before any money moves.

- **Binding:** login returns a single-use binding token (5 min). The app makes the key (`.privateKeyUsage` + `.biometryCurrentSet`, CryptoKit `SecureEnclave.P256`) and `POST /v1/devices` stores its public key; the session's tokens are tied to that device. No Face ID: bound without a key, view only.
- **Signing:** canonical JSON (sorted keys, no whitespace) of transfer ID, amount in minor units, currency, recipient, quote and a single-use 60 s nonce, plus a timestamp. The exact bytes go with the signature, so the server never re-creates the app's JSON.
- **Server:** signature with the session's device key, every field against the stored transfer, nonce used up in the same conditional update, all in the confirm's transaction. A refusal changes nothing. A repeat of an already confirmed transfer returns its status, so retries stay safe.
- **Enrolment change:** the key dies for good. The app also compares the Face ID enrolment saved with the key, explains why sending is off, and signing in again binds a new key.

## Alternatives considered

### Option A: Face ID gate in the app, bearer token only
- Lost: the server can't tell a gated request from a scripted one; the gate protects nothing off the device.

### Option B: `.userPresence` (passcode allowed)
- Lost: anyone who knows the passcode approves transfers, and adding a face goes unnoticed.

## Consequences

- **Easier:** a tampered amount, a replayed confirm or a stolen token can't move money (backend tests).
- **Harder:** changing Face ID means signing in again; phones without biometrics can't send.
- **Revisit when:** passkeys or a bank-issued authenticator replace device binding.
