// swift-tools-version: 6.0
// Tools version 6.0 puts every target in the Swift 6 language mode, so complete
// strict concurrency checking applies everywhere (ADR-014).

import PackageDescription

// Module boundaries from docs/SPEC.md section 3. A target can only import what is
// listed here, so a forbidden import fails to compile. Build with
// `--explicit-target-dependency-import-check error` so SwiftPM does not let an
// undeclared sibling module slip through just because it was already built.
enum Module {
    // Core
    static let domain = "Domain"
    static let designSystem = "DesignSystem"
    static let navigation = "Navigation"
    static let networking = "Networking"
    static let security = "WalletSecurity"
    static let persistence = "Persistence"
    static let observability = "Observability"
    // SDK
    static let identitySDK = "IdentitySDK"
    // Features
    static let authFeature = "AuthFeature"
    static let onboardingFeature = "OnboardingFeature"
    static let accountsFeature = "AccountsFeature"
    static let transferFeature = "TransferFeature"
}

let featureCore: [Target.Dependency] = [
    .target(name: Module.domain),
    .target(name: Module.designSystem),
    .target(name: Module.navigation),
    .target(name: Module.observability),
]

let targets: [Target] = [
    // Core
    .target(name: Module.domain),
    .target(name: Module.observability),
    .target(name: Module.designSystem, dependencies: [.target(name: Module.domain)]),
    .target(name: Module.navigation, dependencies: [.target(name: Module.domain)]),
    // Only Networking may depend on NetworkingKit (ADR-012).
    .target(
        name: Module.networking,
        dependencies: [
            .target(name: Module.domain), .target(name: Module.observability),
            .product(name: "NetworkingKit", package: "NetworkingKit"),
        ]
    ),
    .target(
        name: Module.security,
        dependencies: [.target(name: Module.domain), .target(name: Module.observability)]
    ),
    .target(
        name: Module.persistence,
        dependencies: [.target(name: Module.domain), .target(name: Module.observability)]
    ),

    // SDK: Apple frameworks only, must build alone.
    .target(name: Module.identitySDK),

    // Features: Core only, never another feature.
    .target(name: Module.authFeature, dependencies: featureCore),
    .target(
        name: Module.onboardingFeature, dependencies: featureCore + [.target(name: Module.identitySDK)]),
    .target(name: Module.accountsFeature, dependencies: featureCore),
    .target(name: Module.transferFeature, dependencies: featureCore),
]

let modules = targets.map(\.name)

let package = Package(
    name: "WalletKit",
    defaultLocalization: "en",
    // macOS is declared only so `swift test` runs on the host and in CI.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: modules.map { .library(name: $0, targets: [$0]) },
    // Standalone generic HTTP package next to WalletKit (ADR-012).
    dependencies: [.package(path: "../NetworkingKit")],
    targets: targets
        + modules.map { .testTarget(name: "\($0)Tests", dependencies: testDependencies($0)) }
)

/// Each test target sees its own module. NetworkingTests also sees NetworkingKit so it
/// can stub the transport under `WalletAPI`.
func testDependencies(_ module: String) -> [Target.Dependency] {
    var dependencies: [Target.Dependency] = [.target(name: module)]
    if module == Module.networking {
        dependencies.append(.product(name: "NetworkingKit", package: "NetworkingKit"))
    }
    return dependencies
}
