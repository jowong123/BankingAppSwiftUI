# ADR-014: Swift 6 strict concurrency everywhere

- **Status:** Proposed
- **Date:** 2026-10-24
- **Related:** SPEC sections 2 and 4, ADR-004, ADR-013

## Context

The app keeps shared mutable state that must not race: session tokens (`SessionStore`), balances (`BalanceStore`) and the transfer outbox (`TransferOutbox`). A data race there could show the wrong balance or submit a transfer twice. Swift 6 language mode turns data-race checks into compile errors. Xcode 26 templates also turn on "approachable concurrency" and default `MainActor` isolation, but only for the app target.

## Decision

Every target, in the package and in the app, compiles in Swift 6 language mode with the same concurrency rules.

- `WalletKit/Package.swift` uses `swift-tools-version: 6.0`, which puts every package target in Swift 6 mode.
- The app and its test targets set `SWIFT_VERSION = 6.0`.
- `SWIFT_APPROACHABLE_CONCURRENCY` and `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` are removed from the app target. Package targets can't opt into the same defaults with tools 6.0, and code moving between the app and a module shouldn't change meaning. UI types are marked `@MainActor` explicitly.
- `@unchecked Sendable` and `nonisolated(unsafe)` need a comment on the same line linking an ADR. The SwiftLint rule `no_unchecked_sendable` enforces this.

## Alternatives considered

### Option A: Swift 5 mode in some modules
- Keep hard modules (for example a UIKit wrapper or the NFC code in `IdentitySDK`) on Swift 5 with warnings.
- Lost because the riskiest code would be the least checked, and "temporary" Swift 5 modules tend to stay that way.

### Option B: Xcode 26 defaults (MainActor by default) in the app only
- Less annotation noise in the app target.
- Lost because the same code would mean different things in the app and in `WalletKit`, and the app target is meant to stay thin anyway.

## Consequences

- **Easier:**
  - Races are compile errors.
  - Isolation is visible in the code.
  - The rules are the same in every module.
- **Harder:**
  - More explicit `@MainActor` and `Sendable` work.
  - Some Apple APIs (CoreNFC, older delegate APIs) need wrappers or an ADR-backed exception.
- **Revisit when:** a tools version lets the package adopt approachable concurrency or default isolation per target. At that point, choose one setting for all targets.
