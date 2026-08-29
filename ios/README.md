# Voxa iOS/iPadOS

The iPhone and iPad app lives under this directory as a Swift package at
`ios/VoxaApp/`.

## Scope / status

This is the **Swift package foundation** for the app: the navigation shell,
module boundaries, and tests. It compiles for iPhone/iPad simulators and is
covered by `swift test`, but it is **not yet an installable app bundle**.

Producing a runnable, installable app requires a minimal Xcode app project/
target that hosts `RootView`. That is deliberately a **follow-up**, because the
`ios-testflight.yml` workflow detects any Xcode project on `main` and then
requires Apple signing secrets (see below), which are not configured yet.
Adding the app target should be coordinated with configuring those secrets so
`main` stays green.

## Minimum supported OS

- iOS 17.0
- iPadOS 17.0

iPhone and iPad support is required from the start. `macOS 14` is declared in
`Package.swift` **only** so the package compiles and its logic tests run on the
macOS CI host via `swift test`; there is no macOS product.

## Package layout

`ios/VoxaApp/` is a multi-module Swift package establishing the app's boundaries:

| Module | Responsibility |
| --- | --- |
| `VoxaAppShell` | SwiftUI app entry point and adaptive navigation shell. |
| `VoxaDomain` | Domain models (contracts defined in issue #14). |
| `VoxaNetworking` | Voxa backend networking boundary (contracts in #14). Clients call the Voxa backend only, never OpenAI directly. |
| `VoxaPersistence` | On-device learner-state persistence boundary (strategy in #21/#22). |

`VoxaDomain`, `VoxaNetworking`, and `VoxaPersistence` are intentionally thin
module boundaries for now; their concrete types land in their owning issues.

### Adaptive navigation

`RootView` selects the layout from the horizontal size class via
`AdaptiveLayoutResolver`:

- **Compact width** (typically iPhone): a `TabView` over the primary routes.
- **Regular width** (typically iPad): a `NavigationSplitView` sidebar + detail.

The primary routes are **Home, Talk, Learn, Review, Progress, and Settings**
(`AppRoute`). The selected route is held in `AppNavigationModel`, so it is
preserved when the layout switches on rotation or multitasking size changes.

## Build and test

```bash
# Logic tests on the macOS host (this is what CI runs)
swift test --package-path ios/VoxaApp

# Compile the app shell for an iPhone/iPad simulator destination
xcodebuild -scheme VoxaAppShell -destination 'generic/platform=iOS Simulator' build
```

## TestFlight

The TestFlight workflow skips until an Xcode project or workspace exists under
`ios/`. This Swift package does not by itself trigger a TestFlight upload; an
Xcode app target/project (and the secrets below) are still required.

Expected repository secrets before enabling TestFlight uploads:

- `VOXA_APP_IDENTIFIER`
- `VOXA_APPLE_ID`
- `VOXA_ITC_TEAM_ID`
- `VOXA_TEAM_ID`
- `MATCH_GIT_URL`
- `MATCH_PASSWORD`
- `MATCH_KEYCHAIN_PASSWORD`
- `MATCH_GIT_BASIC_AUTHORIZATION`
- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_API_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_BASE64`
- `VOXA_XCODE_PROJECT` or `VOXA_XCODE_WORKSPACE`
- `VOXA_XCODE_SCHEME`
