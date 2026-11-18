# ADR-024: App Attest, verified on the server with swift-certificates

- **Status:** Accepted
- **Date:** 2026-11-14
- **Related:** SPEC section 6, ADR-008, ADR-016, ADR-023

## Context

A signature proves the device key approved the transfer, not that the request came from our app. A repackaged app, or a script with a stolen key handle, should be refused (threat model: tampered app). Apple's App Attest proves a key lives in a genuine copy of the app on a real device. The server must check the attestation's certificate chain to Apple's root, which needs X.509 parsing.

## Decision

The app attests at binding and adds an assertion to every confirm; the backend verifies both itself, using Apple's `swift-certificates` and `swift-asn1` (already in the tree through Vapor) and a small hand-written CBOR decoder.

- **Binding:** client data is `"<binding token>.<signing key>"`, so the attestation vouches for this key and can't be reused. Checks: chain to the Apple App Attestation root (embedded, fingerprint in the source), nonce extension, key ID = SHA-256 of the key, `rpIdHash` = SHA-256 of `APP_ATTEST_APP_ID`, counter 0, the production AAGUID (the development one only with `APP_ATTEST_ENV=development`). In apple mode a device bound without attestation is refused at challenge and confirm.
- **Confirm:** an assertion over the payload bytes; its signature, `rpIdHash`, and a counter higher than the stored one, updated conditionally.
- Tests build their own root and attestations, so every rule is exercised without a phone.

## Alternatives considered

### Option A: A third-party App Attest package
- Lost: a new, small, unaudited dependency for security-critical code; swift-certificates is Apple's and already resolved.

### Option B: DeviceCheck only
- Lost: two bits per device, no proof per request.

### Option C: Skip App Attest
- Lost: SPEC section 6 and the "tampered app" threat require it.

## Consequences

- **Easier:** binding and every confirm prove the app is genuine; replayed assertions fail on the counter.
- **Harder:** device testing needs the App Attest capability on a paid team; the receipt (fraud metric) isn't used yet.
- **Revisit when:** the receipt's risk metric is wanted (Phase 9), or Apple changes the attestation format.
