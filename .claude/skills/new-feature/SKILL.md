---
name: new-feature
description: Scaffold a new feature module in WalletKit following the project's MVVM + router pattern. Use when the user says /new-feature <Name> or asks to add a new feature module or flow.
argument-hint: <FeatureName without the Feature suffix, e.g. Settings>
---

# Scaffold a feature module

Feature name: **$ARGUMENTS** → module `$ARGUMENTSFeature`.

## 1. Package.swift

Add a library target and test target. Dependencies: only the Core modules this feature needs (usually `Domain`, `DesignSystem`, `Navigation`, `Observability`). Never another `*Feature`.

```swift
.target(name: "$ARGUMENTSFeature", dependencies: ["Domain", "DesignSystem", "Navigation", "Observability"]),
.testTarget(name: "$ARGUMENTSFeatureTests", dependencies: ["$ARGUMENTSFeature"]),
```

## 2. Files in `WalletKit/Sources/$ARGUMENTSFeature/`

```
$ARGUMENTSRoute.swift            public enum, Hashable, Sendable — one case per screen
$ARGUMENTSRouter.swift           @Observable @MainActor final class
$ARGUMENTSDependencies.swift     public struct of protocols (Sendable)
$ARGUMENTSFlowView.swift         the only public view: NavigationStack(path:) + navigationDestination
Screens/<Screen>View.swift
Screens/<Screen>ViewModel.swift
Errors/$ARGUMENTSError.swift
Resources/Localizable.xcstrings  (en + zh-Hans)
```

## 3. Shapes to follow

```swift
@Observable @MainActor
public final class $ARGUMENTSRouter {
    public var path = NavigationPath()
    public var sheet: $ARGUMENTSRoute?
    public init() {}
    public func push(_ route: $ARGUMENTSRoute) { path.append(route) }
    public func pop() { if !path.isEmpty { path.removeLast() } }
    public func popToRoot() { path = NavigationPath() }
    public func present(_ route: $ARGUMENTSRoute) { sheet = route }
    public func dismiss() { sheet = nil }
}

public struct $ARGUMENTSFlowView: View {
    // router, dependencies, and output closures for anything that leaves this feature
    public init(router: $ARGUMENTSRouter, dependencies: $ARGUMENTSDependencies, onFinish: @escaping @MainActor () -> Void)
}

@Observable @MainActor
final class <Screen>ViewModel {
    struct State: Equatable { /* everything the view renders */ }
    private(set) var state = State()
    init(dependencies: $ARGUMENTSDependencies, router: $ARGUMENTSRouter)
    func onAppear() async
    // one async method per user action; map errors to UserFacingError
}
```

## 4. Tests in `WalletKit/Tests/$ARGUMENTSFeatureTests/`

- One Swift Testing suite per view model: initial state, each action, error mapping, cancellation.
- Router tests: push/pop/popToRoot/present.
- Use mock dependencies; no network.

## 5. Wire it up

- Add a factory in `Wallet/AppEnvironment.swift` building `$ARGUMENTSDependencies`.
- Add the flow to `Wallet/AppCoordinator.swift`, handling its output closures.

Then run `swift build`, `swift test`, `swiftlint --strict` and report results.
