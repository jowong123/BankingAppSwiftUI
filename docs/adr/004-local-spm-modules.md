# ADR-004: Local SPM modules; features never import features

- **Status:** Accepted
- **Date:** 2026-10-24
- **Related:** SPEC section 3, ADR-013, ADR-014

## Context

The app has four features (Auth, Onboarding, Accounts, Transfer), seven Core modules and a standalone `IdentitySDK`. Security-sensitive code (Keychain, Secure Enclave signing, pinning) must stay out of UI code, and the SDK must build alone so it can ship separately. Folder conventions can't enforce that. Reviewers for DBS and Thales will look for boundaries that the build itself enforces.

## Decision

All code lives in one local package, `WalletKit`, with one target per module. `Package.swift` dependencies encode SPEC section 3, so a forbidden import fails to compile.

- Features depend on `Domain`, `DesignSystem`, `Navigation` and `Observability`. `OnboardingFeature` also depends on `IdentitySDK`.
- Features do not depend on `Networking`, `Persistence` or `WalletSecurity`. They use protocols declared in `Domain`, and `AppEnvironment` injects the implementations.
- Cross-feature navigation goes through output closures handled by `AppCoordinator`.
- Builds use `--explicit-target-dependency-import-check error`. Without it, a warm `.build` cache lets a target import an undeclared sibling.
- `scripts/check-module-boundaries.sh` runs in CI. It checks that every forbidden import fails and that one allowed import compiles.
- The security module is `WalletSecurity`, not `Security`. A module named `Security` shadows Apple's Security.framework.

## Alternatives considered

### Option A: single app target with folders
- Simplest setup. Every file can see every other file.
- Lost because boundaries are only conventions, so one stray import couples Transfer to Auth with no compiler error. It also can't prove that `IdentitySDK` builds alone.

### Option B: separate packages or frameworks per module
- Each module gets its own `Package.swift` or Xcode framework target.
- Lost because 12 manifests and their version wiring cost a lot for a solo project, with no extra enforcement over targets in one package.

## Consequences

- **Easier:**
  - Boundaries fail at compile time.
  - Modules build and test in isolation with `swift test`.
  - The SDK can be extracted later.
- **Harder:**
  - Shared code needs a deliberate home in Core.
  - Domain protocols add a layer between features and infrastructure.
  - The boundary script needs updating when a module is added.
- **Revisit when:** a feature genuinely needs infrastructure that a Domain protocol can't express, or build times call for binary caching (see ADR-013).
