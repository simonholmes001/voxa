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
| `VoxaAppShell` | Adaptive navigation shell (`RootView`, routes, layout resolver), auth- and onboarding-gated. |
| `VoxaAuth` | Sign in with Apple UI, session lifecycle, and secure Keychain token storage. |
| `VoxaOnboarding` | First-run onboarding flow, CEFR placement estimate, and resumable draft. |
| `VoxaRealtime` | Talk-screen Realtime voice session: mic permission, connection state machine, session/transport seams, and `TalkView`. |
| `VoxaDomain` | Domain models (contracts defined in issue #14). |
| `VoxaNetworking` | Backend HTTP clients (e.g. `VoxaBackendAuthenticationService` for `/api/auth/*`). Clients call the Voxa backend only, never OpenAI directly. |
| `VoxaPersistence` | On-device learner-state persistence boundary (strategy in #21/#22). |

`VoxaDomain`, `VoxaNetworking`, and `VoxaPersistence` are intentionally thin
module boundaries for now; their concrete types land in their owning issues.

## Dependencies

The iOS app has one external binary dependency: **WebRTC** for live voice tutoring.

### WebRTC (stasel/WebRTC)

- **Package**: https://github.com/stasel/WebRTC
- **Version**: 151.0.0 (pinned, not floating)
- **License**: BSD 3-Clause (permissive, compatible with commercial use)
- **Purpose**: Enables live voice tutoring by establishing direct WebRTC peer connections to OpenAI Realtime API
- **Size impact**: ~42MB xcframework (compressed); ~15-20MB per architecture after App Store thinning

**Why this dependency:**
- OpenAI Realtime API requires WebRTC for voice sessions (SDP offer/answer, ICE, peer connection, audio transport)
- AVFoundation alone is insufficient — it handles audio capture but not the WebRTC protocol stack
- `stasel/WebRTC` is a community-maintained binary distribution built directly from official Google WebRTC sources with zero modifications
- Active maintenance (latest release: Aug 31, 2026), tracks Chromium releases, widely used in production iOS apps
- Binary-only distribution accepted as pragmatic choice for rapid integration; source audit limited to upstream Google WebRTC

**Integration boundary:**
- Isolated behind the `RealtimeTransport` protocol seam in `VoxaRealtime` module
- Not used outside live Talk sessions
- Tests mock the transport boundary; WebRTC itself is not unit-tested (upstream responsibility)

### Authentication (Sign in with Apple)

`RootView` gates the navigation shell behind authentication: when signed out it
shows `SignInView` (Sign in with Apple); once signed in it shows the shell.
`AuthViewModel` owns the session lifecycle — restore on launch, exchange,
refresh, sign out — persisting tokens through a `SessionStore`
(`KeychainSessionStore` in the app, `EphemeralSessionStore` for tests/previews).

The backend exchange is implemented by `VoxaBackendAuthenticationService`
(`VoxaNetworking`) against `POST /api/auth/apple`, `/api/auth/refresh`, and
`/api/auth/logout` (see `docs/api-contracts.md`). The wire DTOs are isolated in
`VoxaNetworking` so a contract change stays contained. `AuthSession` tracks both
`expiresAt` and `refreshTokenExpiresAt`, so a dead refresh token forces a fresh
sign-in instead of a failed refresh. Sign in with Apple uses a per-request nonce
(SHA-256 hashed for Apple, raw value sent to the backend).

Configuration and requirements:

- **Backend base URL** comes from the Info.plist key `VOXA_API_BASE_URL`
  (driven by the `VOXA_API_BASE_URL` build setting; empty by default). When it
  is blank, `AppComposition` injects the `NotConfigured*` services, so sign-in
  and Realtime fail clearly instead of silently doing nothing.
  - **Local/device testing:** copy `ios/Voxa/Config/Debug.local.xcconfig.example`
    to `ios/Voxa/Config/Debug.local.xcconfig` (git-ignored) and set
    `VOXA_API_BASE_URL = https://<your-function-app>...`. The committed
    `Debug.xcconfig` includes it optionally, so no real URL is ever committed.
  - **CI / one-off:** pass `VOXA_API_BASE_URL=...` on the `xcodebuild` command
    line, or supply it via Fastlane.
- The **Sign in with Apple** capability is declared in
  `ios/Voxa/Voxa.entitlements` (`com.apple.developer.applesignin`); the App ID
  must have the capability enabled for signed device/TestFlight builds.

### Onboarding and placement

After sign-in, `RootView` shows onboarding until it is complete. `OnboardingView`
is a short stepped flow (target/native language, goal, daily time, a quick
placement, summary). `OnboardingViewModel` persists a resumable `OnboardingDraft`
after every answer via an `OnboardingDraftStore`
(`UserDefaultsOnboardingDraftStore` in the app, `InMemoryOnboardingDraftStore`
for tests/previews), so an interrupted onboarding resumes on the same device.

`PlacementEstimator` produces a deterministic initial CEFR estimate from a short
"can-do" self-assessment ladder. Onboarding **completes locally** by default
(`LocalOnboardingService`); wiring the `POST /api/onboarding` backend client and
cross-device resume is tracked as a separate follow-up issue.

### Talk screen (Realtime voice session)

> **Scope:** this provides the **Talk UI and the Realtime session-credential
> client only**. It does **not** implement live audio yet — there is no WebRTC
> transport, so you cannot actually speak to the tutor on device. Live audio is
> a separate follow-up (see below), so the app must not be treated as
> voice-testable from this work.

The Talk route hosts `TalkView`, driven by `TalkSessionViewModel`
(`VoxaRealtime`). Starting a session runs an explicit lifecycle:

`idle → requestingSession → connecting → connected` (and `failed(reason)` /
`ended`).

The flow: request **microphone permission** (`MicrophonePermission`; the app
uses `SystemMicrophonePermission` backed by `AVAudioApplication`), then request
a short-lived credential from `POST /api/realtime/session`
(`VoxaBackendRealtimeSessionService`, authenticated with the app-session access
token), then hand the credential to a `RealtimeTransport` to establish the
direct WebRTC connection to OpenAI Realtime. The permanent OpenAI key stays
server-side. Session settings (target language, proficiency band) are derived
from the learner's onboarding state at `start()` time, not hard-coded.

The concrete WebRTC transport (`WebRTCRealtimeTransport`) uses the
`stasel/WebRTC` package (see Dependencies above) to establish the media session.
Audio route/interruption/reconnect handling is implemented; transcript capture
and session summaries are deferred to follow-up work.

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

# Build the installable app for an iPhone or iPad simulator.
# Simulator builds don't need signing; pass CODE_SIGNING_ALLOWED=NO as a
# command-line override (the project itself uses automatic signing so device/
# TestFlight builds still work).
xcodebuild -project ios/Voxa.xcodeproj -scheme Voxa \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build CODE_SIGNING_ALLOWED=NO

# Run the app target's hosted unit tests on a simulator
xcodebuild -project ios/Voxa.xcodeproj -scheme Voxa \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test CODE_SIGNING_ALLOWED=NO
```

Signing is **not** disabled at the project level: the app uses automatic signing
driven by `DEVELOPMENT_TEAM` (supplied via CI/Fastlane match) for device and
Release/TestFlight builds. Only simulator/CI invocations override
`CODE_SIGNING_ALLOWED=NO` on the command line.

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
