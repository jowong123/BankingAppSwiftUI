# ADR-006: TLS public-key pinning with a backup pin

- **Status:** Accepted
- **Date:** 2026-11-14
- **Related:** SPEC section 6, ADR-012, ADR-021

## Context

A banking app can't rely on the system trust store alone. A user (or an attacker who controls the device's settings) can install a root certificate and read traffic through a proxy, including the signed confirm. NetworkingKit must stay Foundation-only (ADR-012), and the sandbox backend in Debug is plain http on localhost (ADR-018).

## Decision

Every TLS connection to the API host must pass the system's normal checks and present a key whose SubjectPublicKeyInfo SHA-256 is one of the pins in `WalletAPIPins` (Info.plist): the current key and a backup kept offline.

- `PinningPolicy` (NetworkingKit) checks every certificate in the chain; the caller supplies SHA-256, so NetworkingKit imports nothing but Foundation. `Networking` passes CryptoKit's.
- A per-request delegate cancels the handshake on a mismatch and records it, so the error is `HTTPError.pinningFailed`, never a cancel. It is not retried and shows as "Can't reach Wallet".
- A pinned host with no pins fails closed. Release has none until the Phase 9 server exists, so Release can't talk to anything. Debug http has no TLS and nothing to pin.

## Alternatives considered

### Option A: Pin the certificate
- Every renewal needs an app update first, or users are locked out.
- Lost: pinning the key survives renewals on the same key.

### Option B: No pinning, trust store only
- Lost: a user-installed root defeats it; fails the "man in the middle" row of the threat model.

### Option C: A pinning library (TrustKit)
- Lost: a new dependency for about 80 lines (ADR-012).

## Consequences

- **Easier:** a proxy with its own trusted root sees nothing; tests check hashes against openssl's.
- **Harder:** a key rotation needs the backup pin shipped first; losing both keys locks every installed app out until an update.
- **Revisit when:** a deployed server exists (fill the pins, Phase 9), or certificates come from a CDN whose keys we don't control.
