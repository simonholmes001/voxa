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
        .library(name: "VoxaAuth", targets: ["VoxaAuth"]),
        .library(name: "VoxaOnboarding", targets: ["VoxaOnboarding"]),
        .library(name: "VoxaRealtime", targets: ["VoxaRealtime"]),
        .library(name: "VoxaHome", targets: ["VoxaHome"]),
        .library(name: "VoxaDomain", targets: ["VoxaDomain"]),
        .library(name: "VoxaNetworking", targets: ["VoxaNetworking"]),
        .library(name: "VoxaPersistence", targets: ["VoxaPersistence"]),
    ],
    dependencies: [
        // WebRTC for OpenAI Realtime voice sessions. Pinned to 151.x (not floating to latest).
        // See ios/README.md Dependencies section for rationale, license, and size impact.
        .package(url: "https://github.com/stasel/WebRTC.git", from: "151.0.0"),
    ],
    targets: [
        .target(name: "VoxaDomain"),
        .target(name: "VoxaNetworking", dependencies: ["VoxaDomain", "VoxaAuth", "VoxaOnboarding", "VoxaRealtime"]),
        .target(name: "VoxaPersistence", dependencies: ["VoxaDomain"]),
        .target(name: "VoxaAuth", dependencies: ["VoxaDomain"]),
        .target(name: "VoxaOnboarding", dependencies: ["VoxaDomain"]),
        .target(
            name: "VoxaRealtime",
            dependencies: [
                "VoxaDomain",
                .product(name: "WebRTC", package: "WebRTC"),
            ]
        ),
        .target(name: "VoxaHome", dependencies: ["VoxaDomain"]),
        .target(
            name: "VoxaAppShell",
            dependencies: ["VoxaDomain", "VoxaNetworking", "VoxaPersistence", "VoxaAuth", "VoxaOnboarding", "VoxaRealtime", "VoxaHome"]
        ),
        .testTarget(name: "VoxaAppShellTests", dependencies: ["VoxaAppShell"]),
        .testTarget(name: "VoxaAuthTests", dependencies: ["VoxaAuth"]),
        .testTarget(name: "VoxaNetworkingTests", dependencies: ["VoxaNetworking"]),
        .testTarget(name: "VoxaOnboardingTests", dependencies: ["VoxaOnboarding"]),
        .testTarget(name: "VoxaRealtimeTests", dependencies: ["VoxaRealtime"]),
        .testTarget(name: "VoxaHomeTests", dependencies: ["VoxaHome"]),
        .testTarget(name: "VoxaDomainTests", dependencies: ["VoxaDomain"]),
    ],
    swiftLanguageModes: [.v5]
)
