# ADR-013: Plain Xcode project + local SPM; Tuist at team scale

- **Status:** Proposed
- **Date:** 2026-10-24
- **Related:** SPEC sections 2 and 3, ADR-004

## Context

ADR-004 splits the code into 12 modules. Something has to define those targets and wire them into the app target. The project is built by one person, and anyone cloning it should be able to open it in Xcode without installing extra tools. CI runs on GitHub's macOS runners.

## Decision

`Wallet.xcodeproj` holds only the app target and its two test targets. All modules live in the local package `WalletKit/Package.swift`, which the project references as a local package.

- The project uses file-system synchronised groups, so adding a file under `Wallet/` needs no edit to the project file.
- `WalletKit` exposes one library product per module. The app links the 11 products it uses directly. It reaches `IdentitySDK` only through `OnboardingFeature`.
- The package declares iOS 17, plus macOS 14 so `swift test` runs on the host and in CI without a simulator.
- Xcode generates the `Wallet` scheme automatically, so no shared scheme is committed.

## Alternatives considered

### Option A: Tuist from day one
- Generates the Xcode project from Swift manifests and adds caching and dependency graphs.
- Lost because it adds a tool to install, a generate step and a project file that isn't committed. For one developer and one app target that costs more than it saves, and SwiftPM already enforces the module graph.

### Option B: XcodeGen
- Generates the project from YAML.
- Lost because synchronised groups already remove most merge conflicts in the project file, which was XcodeGen's main benefit, and YAML gives no type checking.

### Option C: Xcode framework targets instead of a package
- Each module as a framework target inside `Wallet.xcodeproj`.
- Lost because module tests then need a simulator, the project file grows with every module, and `swift test` can't run them.

## Consequences

- **Easier:**
  - Clone, open, run.
  - `swift test` covers every module.
  - The project file stays small.
- **Harder:**
  - Linking a new module product means editing the project once in Xcode.
  - There is no build cache across machines.
- **Revisit when:** the team grows past a handful of engineers, there are several app targets (widgets, App Clip), or clean CI builds become slow enough that Tuist's binary cache pays off.
