# ADR-005: Manual constructor injection from one composition root

- **Status:** Proposed
- **Date:** 2026-11-08
- **Related:** SPEC sections 2 and 4, ADR-002, ADR-004

## Context

Features may not import `Networking`, `WalletSecurity` or `Persistence` (ADR-004), yet the sign-in screen must reach the Keychain-backed session and the accounts list must reach the API. Something has to create the concrete objects and hand them over. In a banking app it also matters that there is exactly one session and one HTTP client: two `AuthInterceptor`s would refresh the same rotating token in parallel and sign the user out (ADR-016).

## Decision

`Wallet/AppEnvironment.swift` is the only place that creates concrete dependencies; everything else receives protocols through its initialiser.

- `AppEnvironment.live()` runs once at launch. It builds one `SessionStore` (with `RemoteAuthAPI`, `KeychainStore`, `DeviceBiometrics`), one `WalletAPI` that takes the same session as its `SessionTokenProvider`, and `RemoteAccountsRepository`. It makes no network calls itself.
- Each feature declares a `<Name>Dependencies` struct of Domain protocols (`AuthDependencies.session: any SessionManaging`, `AccountsDependencies.repository`). The path is `AppEnvironment` → `AppCoordinator` → `<Name>FlowView` → screen → view model `init`.
- Results go back up through output closures (`onSessionChange`, `onSessionExpired`), not through shared objects.
- Debug `-mockServer` builds `MockAuthAPI`, `InMemorySecureStore`, `NoBiometrics` and `MockAccountsRepository` instead; nothing below `AppEnvironment` changes.
- Tests and previews pass fakes straight into the view model or coordinator.

## Alternatives considered

### Option A: swift-dependencies or Factory
- A library resolves dependencies by key, often through a global container or task-local values.
- Lost because it adds a third-party dependency for a dozen objects, and a missing registration shows up at runtime rather than at compile time. It also works like a service locator, which the hard rules ban.

### Option B: Singletons (`SessionStore.shared`)
- Each service is a global any code can reach.
- Lost because features could then reach WalletSecurity around the module rules, tests would share state between runs, and nothing would stop a second `WalletAPI` from being built.

## Consequences

- **Easier:** every dependency is visible in an `init` and checked by the compiler. Tests swap any piece without setup code. The real, mock and unconfigured wirings sit side by side in one file.
- **Harder:** adding a dependency means touching each `init` along the path; the `Dependencies` structs keep that to one field per feature.
- **Revisit when:** the graph outgrows one readable file (tens of features, per-flow scopes).
