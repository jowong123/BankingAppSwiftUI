# Wallet — iOS fintech portfolio project

Multi-currency wallet app (Wise-style send flow, bank-grade security) portfolio piece targeting DBS, Wise and Thales. Fake money and sandbox services only.

The full spec is in `docs/SPEC.md`. Read the relevant section before starting any task. If this file and the spec disagree, the spec wins; flag the conflict.

## Stack (do not change without an ADR)

- Swift 6, **strict concurrency in every module**, iOS 17 minimum
- SwiftUI-first; UIKit only behind wrappers (NFC, camera, screenshot masking)
- MVVM + Coordinators: `@Observable` view models, one `@Observable` router per flow owning a `NavigationPath`
- Local SPM package `WalletKit` holds all modules; the Xcode project contains only the app target
- SwiftData cache (`.complete` file protection), Keychain for secrets, Secure Enclave for signing keys
- Custom `URLSession` client with an interceptor chain; Vapor backend in `backend/`
- Manual constructor injection, wired in `Wallet/AppEnvironment.swift`
- Swift Testing for unit tests, XCUITest for flows
- SwiftLint + swift-format; GitHub Actions + Fastlane; OßSLog + Sentry

## Architecture

```
Wallet/              app target: WalletApp, AppCoordinator, AppEnvironment
WalletKit/           local SPM package — all modules + tests
  Sources/<Module>/  AuthFeature, OnboardingFeature, AccountsFeature, TransferFeature,
                     Domain, DesignSystem, Navigation, Networking, WalletSecurity,
                     Persistence, Observability, IdentitySDK
  Tests/<Module>Tests/
NetworkingKit/       standalone package: generic HTTP client + interceptors (ADR-012)
backend/             Vapor service + openapi.yaml
docs/                SPEC.md, adr/, threat-model.md
```

## Hard rules

- Never use `Double`/`Float` for money. Use `Money` (Decimal) from Domain; `amountMinor: Int64` at the API boundary.
- Never store secrets in UserDefaults, SwiftData, files or source. Use `WalletSecurity/KeychainStore`.
- Never log PII. Use `Logger` from Observability; interpolations default to `privacy: .private`. `print` is banned.
- No singletons, no service locators. Inject through initialisers.
- No `!` force unwraps or `try!` outside tests.
- No new third-party dependency without a new ADR.
- No `@unchecked Sendable` / `nonisolated(unsafe)` without a comment linking an ADR.
- Never weaken a security control (pinning, signing, App Attest, file protection) to make something work. Stop and ask.
- Mutating API calls always send an `Idempotency-Key`. A network timeout on a transfer is never treated as failed — check status first.

## Rules (enforced by Package.swift)

- **Features never import other features.** Cross-feature navigation = output closures handled by `AppCoordinator`.
- Features never import `Networking`, `Persistence` or `WalletSecurity`. They use protocols in `Domain`; `AppEnvironment` injects the implementations (ADR-004).
- `Domain` imports Foundation only. No SwiftUI, no networking.
- `DesignSystem` imports SwiftUI + Domain only.
- `Networking`, `WalletSecurity`, `Persistence` import Domain + Observability only. `Networking` also imports `NetworkingKit`; nothing else does.
- `NetworkingKit` imports Foundation only — nothing from WalletKit. Wallet-specific endpoints and DTOs live in `Networking` (ADR-012).
- `IdentitySDK` imports Apple frameworks only — nothing from WalletKit. It must build alone.
- If a task seems to need a forbidden import, stop and propose where the shared code should live.

## Feature module pattern

Each feature has:
- `<Name>Route` — `Hashable` enum of screens
- `<Name>Router` — `@Observable @MainActor`, owns `NavigationPath` + sheet/cover state
- `<Name>Dependencies` — struct of protocols the feature needs
- `<Name>FlowView` — the single public entry point, takes router, dependencies and output closures
- One `ViewModel` per screen: `@Observable @MainActor`, one `State` struct, async methods, maps errors to `UserFacingError`
- Views contain no business logic and never navigate except through the router

Use the `/new-feature` skill to scaffold one.

## Workflow

1. Restate the task and list the files you will create or change before writing code.
2. Write or update tests in the same change. Money, state machine and security code need tests for edge cases.
3. Run the relevant build, tests and lint before saying you're done. Report what you ran and the result.
4. If a decision isn't covered by `docs/SPEC.md`, stop and ask, or propose an ADR with `/adr`. Don't guess.
5. Keep changes to one concern. Suggest a conventional commit message (`feat(transfer): ...`) at the end. Work for a build phase puts the phase number in front, e.g. `phase 2: feat(domain): add Money, Currency, FX types and transfer state machine with tests`.
6. Explain non-obvious code briefly in your summary — the owner must be able to defend every line in an interview.

## Skills and agents in this repo

- `/phase <n>` — run a build phase from the plan in `docs/SPEC.md` and verify its "done when" checks
- `/new-feature <Name>` — scaffold a feature module using the pattern above
- `/adr <number> <title>` — write an ADR from the template
- `security-reviewer` agent — review changes touching auth, signing, storage, networking or logging
- `architecture-reviewer` agent — check module boundaries, concurrency and conventions before a PR
