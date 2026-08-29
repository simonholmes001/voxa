// swift-tools-version: 6.0
import PackageDescription

// Voxa iPhone and iPad app package.
//
// Product platforms are iOS and iPadOS 17+. macOS is declared only so the
// package compiles and its logic tests run on the macOS CI host via
// `swift test`; there is no macOS product target.
let package = Package(
    name: "VoxaApp",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "VoxaAppShell", targets: ["VoxaAppShell"]),
        .library(name: "VoxaDomain", targets: ["VoxaDomain"]),
        .library(name: "VoxaNetworking", targets: ["VoxaNetworking"]),
        .library(name: "VoxaPersistence", targets: ["VoxaPersistence"]),
    ],
    targets: [
        .target(name: "VoxaDomain"),
        .target(name: "VoxaNetworking", dependencies: ["VoxaDomain"]),
        .target(name: "VoxaPersistence", dependencies: ["VoxaDomain"]),
        .target(
            name: "VoxaAppShell",
            dependencies: ["VoxaDomain", "VoxaNetworking", "VoxaPersistence"]
        ),
        .testTarget(name: "VoxaAppShellTests", dependencies: ["VoxaAppShell"]),
        .testTarget(name: "VoxaDomainTests", dependencies: ["VoxaDomain"]),
    ],
    swiftLanguageModes: [.v5]
)
