# ADR-019: App PIN checked on the device

- **Status:** Accepted
- **Date:** 2026-11-07
- **Related:** SPEC sections 4 and 6, ADR-008, ADR-016

## Context

SPEC asks for Face ID with a PIN fallback to unlock a saved session (after 5 minutes of inactivity or 2 in the background). The server has no PIN. The PIN must be usable offline, must not be recoverable from the device, and must not let someone holding an unlocked phone guess their way in.

## Decision

After first sign-in the user sets a 6-digit app PIN, verified on the device by `SessionStore`, with 5 attempts before the session is wiped.

- Stored in the Keychain (`WhenUnlockedThisDeviceOnly`, same as the tokens): a random 16-byte salt, a PBKDF2-HMAC-SHA256 hash at 600,000 iterations (OWASP 2023), the iteration count, and the attempts left. Never the PIN.
- Compared in constant time, with the hash computed off the actor so other calls aren't blocked.
- **Each attempt is counted and saved before the PIN is checked.** If that write fails, the PIN isn't checked at all, so a failing Keychain or a killed app never gives a free guess, and a right and a wrong PIN get the same error. Quitting the app doesn't reset the count.
- 5 wrong PINs, or a sign-out, wipe the tokens and the PIN; the user signs in again with their password. The last attempt is saved as zero before the wipe, so a wipe that fails is repeated at the next launch. A correct PIN or Face ID resets the count.
- **Face ID is bound to the enrolment.** The PIN record stores `LAContext.evaluatedPolicyDomainState` from when the PIN was set or last entered. If faces or fingers are added or removed, Face ID is refused (before the prompt, and again on the prompt's result) until the PIN is entered. Someone who knows the phone's passcode can enrol their own face, but can't use it here.
- Face ID uses `deviceOwnerAuthenticationWithBiometrics`, so the device passcode is not accepted in its place; the app PIN is the fallback.
- Tokens with no PIN at launch (the app quit during PIN creation) are wiped. Otherwise whoever holds the phone could set a PIN on someone else's live session. The "create PIN" screen also times out to signed out.
- If the Keychain can't be read at launch (the app started while the phone was locked), nothing is wiped: the app shows "locked" and reads again on unlock.
- A fresh install wipes any session iOS kept in the Keychain from a previous install (a non-secret "has launched" flag in the app's defaults, which deletion removes).
- **Limit:** the PIN and Face ID gate the UI. The Keychain items themselves have no biometric access control, so on a jailbroken device the tokens are readable. Phase 7's Secure Enclave key, which needs Face ID for every signature, protects transfers regardless.

## Alternatives considered

### Option A: Device passcode as the fallback (`deviceOwnerAuthentication`)
- iOS handles it; nothing to store.
- Lost because anyone who knows the phone's passcode (family, a shoulder-surfer) gets into the bank app, and there is no app-level attempt limit to demonstrate.

### Option B: PIN verified by the server
- Server-side attempt limits; a stolen Keychain dump reveals nothing.
- Lost for now: it needs a connection to unlock and new backend endpoints. A six-digit PIN has only 10^6 values, so offline guessing of a leaked hash is cheap even at 600k iterations; our defence is that the record never leaves the Keychain (this-device-only, when-unlocked) and the attempt limit. Phase 7's device-bound Secure Enclave key raises the bar for transfers regardless.

## Consequences

- **Easier:** works offline; one actor owns tokens, PIN and lock state, all unit-tested with fakes.
- **Harder:** unlock takes a few hundred milliseconds for PBKDF2 on device.
- **Revisit when:** the server can verify the PIN (Option B), or device binding (Phase 7) lets the PIN unlock the Secure Enclave key instead.
