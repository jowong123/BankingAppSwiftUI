// swift-tools-version: 6.0
// Swift 6 language mode, like the app (ADR-014).

import PackageDescription

// Sandbox Wallet API (SPEC section 7). Fake money only.
// Fluent sets up SQLite and runs migrations; queries use SQLKit into plain Sendable
// structs, so no Fluent `Model` classes and no unchecked Sendable conformances.
let package = Package(
    name: "WalletBackend",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.12.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.8.0"),
        .package(url: "https://github.com/vapor/sql-kit.git", from: "3.32.0"),
    ],
    targets: [
        .executableTarget(
            name: "WalletBackend",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "SQLKit", package: "sql-kit"),
            ]
        ),
        .testTarget(
            name: "WalletBackendTests",
            dependencies: [
                .target(name: "WalletBackend"),
                .product(name: "XCTVapor", package: "vapor"),
            ]
        ),
    ]
)
