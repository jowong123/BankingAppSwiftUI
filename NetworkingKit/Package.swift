// swift-tools-version: 6.0
// Tools version 6.0 puts the package in the Swift 6 language mode, so complete
// strict concurrency checking applies (ADR-014).

import PackageDescription

// Generic HTTP client + interceptor chain (ADR-012). Foundation only: no dependencies,
// and nothing from WalletKit. Wallet endpoints and DTOs live in WalletKit's `Networking`.
let package = Package(
    name: "NetworkingKit",
    // macOS is declared only so `swift test` runs on the host and in CI.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "NetworkingKit", targets: ["NetworkingKit"])],
    targets: [
        .target(name: "NetworkingKit"),
        .testTarget(name: "NetworkingKitTests", dependencies: ["NetworkingKit"]),
    ]
)
