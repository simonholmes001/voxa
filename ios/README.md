# Voxa iOS/iPadOS

The iPhone and iPad app lives under this directory as a Swift package at
`ios/VoxaApp/`.

## Scope / status

The app is an installable iPhone/iPad target (`ios/Voxa.xcodeproj`, scheme
`Voxa`) that hosts `RootView` from the `VoxaApp` Swift package. It builds for
iPhone and iPad simulators **without** Apple signing secrets. TestFlight upload
stays gated on the signing secrets listed below (the workflow skips, rather
than fails, until they are configured).

## App target and project generation

The Xcode project is generated from `ios/project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen). `ios/Voxa.xcodeproj` is
committed so CI (`validate-ios-project.sh`, Fastlane `gym`) can consume it
without XcodeGen. After editing `project.yml`, regenerate and commit the result:

```bash
cd ios && xcodegen generate
```

Layout:

- `ios/Voxa/` — app target sources: `VoxaApp` (`@main`), `AppComposition`
  (composition root), and `Info.plist` (microphone + speech usage strings).
- `ios/Voxa.xcodeproj` — generated project with the `Voxa` app target and the
  `VoxaTests` hosted unit-test target.
- `ios/VoxaApp/PrivacyInfo.xcprivacy` — app privacy manifest.
- `ios/VoxaApp/` — the Swift package hosting all app logic (see below).

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
| `VoxaAppShell` | Adaptive navigation shell (`RootView`, routes, layout resolver). |
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
# Fast logic tests on the macOS host (run in CI)
swift test --package-path ios/VoxaApp

# Build the installable app for an iPhone or iPad simulator (no signing)
xcodebuild -project ios/Voxa.xcodeproj -scheme Voxa \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build CODE_SIGNING_ALLOWED=NO

# Run the app target's hosted unit tests on a simulator
xcodebuild -project ios/Voxa.xcodeproj -scheme Voxa \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test CODE_SIGNING_ALLOWED=NO
```

## TestFlight

`ios-testflight.yml` runs on push to `main`. It detects the Xcode project and
then **skips** the upload unless the signing secrets below are configured, so
adding the app target does not break `main`. When the secrets exist, the
workflow validates the project/scheme and privacy manifest and uploads an
internal build.

Required repository secrets before TestFlight uploads work:

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
