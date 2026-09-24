# Voxa

[![CI](https://github.com/simonholmes001/voxa/actions/workflows/ci.yaml/badge.svg?branch=main)](https://github.com/simonholmes001/voxa/actions/workflows/ci.yaml)
[![Backend CI](https://github.com/simonholmes001/voxa/actions/workflows/backend-ci.yaml/badge.svg?branch=main)](https://github.com/simonholmes001/voxa/actions/workflows/backend-ci.yaml)
[![iOS CI](https://github.com/simonholmes001/voxa/actions/workflows/ios-ci.yaml/badge.svg?branch=main)](https://github.com/simonholmes001/voxa/actions/workflows/ios-ci.yaml)
[![Azure IaC Lint](https://github.com/simonholmes001/voxa/actions/workflows/iac-lint.yaml/badge.svg?branch=main)](https://github.com/simonholmes001/voxa/actions/workflows/iac-lint.yaml)
[![Release](https://github.com/simonholmes001/voxa/actions/workflows/release.yml/badge.svg?branch=main)](https://github.com/simonholmes001/voxa/actions/workflows/release.yml)
[![TestFlight](https://github.com/simonholmes001/voxa/actions/workflows/ios-testflight.yml/badge.svg?branch=main)](https://github.com/simonholmes001/voxa/actions/workflows/ios-testflight.yml)

Voxa is a voice-first language tutor for iPhone and iPad. It combines a SwiftUI
client with a .NET 10 backend on Azure, short-lived OpenAI Realtime credentials,
personalised learning state, practice and translation tools, review evidence,
and a release path that is validated by GitHub Actions before TestFlight
delivery.

> **Project status:** Voxa is an actively developed MVP. The repository contains
> installable iOS targets, a deployed-backend architecture, infrastructure as
> code, App Store preparation material, and automated release workflows. Some
> product areas and operational controls remain explicitly marked as follow-up
> work in the linked documentation.

## What Voxa does

- Sign in with Apple and maintain a secure Voxa app session.
- Guide a learner through onboarding, goals, daily study time, and CEFR-style
  placement.
- Support multiple language profiles with an active profile selected on the
  server and resumed across devices.
- Provide a realtime voice tutor over WebRTC using a backend-issued,
  short-lived OpenAI client credential.
- Provide guided practice, text/voice/image translation, correction and
  explanation, review, debrief evidence, progress, and language settings.
- Schedule personalised local learning reminders based on the learner's state.
- Expose authenticated account export and deletion operations.
- Run through pull-request validation, path-aware main-branch checks, a release
  gate, and optional TestFlight upload.

## Architecture

```text
                         GitHub Actions
                  CI / backend / iOS / IaC
                              |
                         Release gate
                              |
                         TestFlight

  iPhone / iPad (SwiftUI) ---- HTTPS ----> Azure Functions (.NET 10)
       |                                      |
       | WebRTC with short-lived              +-- Application use cases
       | OpenAI client credential              +-- Domain rules
       |                                      +-- Azure Storage repositories
       +-- Keychain/local draft               +-- Key Vault / managed identity
                                              +-- OpenAI Responses/Realtime

  Bicep infrastructure: Function App, Storage, Key Vault, networking,
  private endpoints/DNS, Application Insights, and Log Analytics.
```

The mobile app never receives the permanent OpenAI API key. Normal API calls
go through Voxa's authenticated backend. The approved realtime path uses the
backend to issue a short-lived client credential and then establishes the media
connection from the app.

## Repository map

| Path | Purpose |
| --- | --- |
| [`ios/`](ios/) | Xcode app target, Swift package modules, Fastlane, privacy manifest, and iOS tests |
| [`backend/`](backend/) | .NET 10 modular monolith and layer-specific tests |
| [`infrastructure/`](infrastructure/) | Azure Bicep templates, deployment, validation, and guard scripts |
| [`docs/api-contracts.md`](docs/api-contracts.md) | Mobile-facing HTTP contracts and common API rules |
| [`docs/specs/`](docs/specs/) | Product and AI behavior specifications |
| [`docs/prompts/`](docs/prompts/) | Versioned prompt registry conventions and examples |
| [`docs/evals/`](docs/evals/) | Deterministic AI evaluation cases and assertion schema |
| [`docs/app-store-privacy-checklist.md`](docs/app-store-privacy-checklist.md) | App Store privacy-answer inventory |
| [`docs/app-store-submission-package.md`](docs/app-store-submission-package.md) | App Review and submission preparation |
| [`docs/testflight-setup.md`](docs/testflight-setup.md) | Signing, App Store Connect secrets, and TestFlight setup |
| [`tests/`](tests/) | Shared test assets and evaluation fixtures |
| [`.github/workflows/`](.github/workflows/) | CI, infrastructure, release, review, and TestFlight workflows |
| [`.changeset/`](.changeset/) | Release-note and semantic-versioning inputs |

## Prerequisites

Install the following before running the full local test matrix:

- macOS with Xcode and the iOS 17 SDK (the app supports iOS 17 and iPadOS 17).
- XcodeGen when changing [`ios/project.yml`](ios/project.yml).
- .NET SDK `10.0.400` or a compatible later feature-band SDK, as selected by
  [`global.json`](global.json).
- Node.js 22 or later and npm.
- Swift toolchain provided by Xcode.
- Azure CLI and Bicep only when validating or deploying infrastructure.
- Ruby/Bundler only when using the Fastlane/TestFlight workflow locally.

Cloud deployment, Apple signing, and App Store Connect operations additionally
require the credentials described in [`infrastructure/README.md`](infrastructure/README.md)
and [`docs/testflight-setup.md`](docs/testflight-setup.md). Never commit those
credentials.

## Quick start

Clone the repository and install the root Node dependencies:

```bash
git clone https://github.com/simonholmes001/voxa.git
cd voxa
npm ci
```

Enable the repository's pre-commit hook once per checkout:

```bash
bash scripts/setup-hooks.sh
```

The hook runs the root Node checks, backend tests, and Swift package tests. A
commit should not bypass it with `--no-verify`.

### Run the test suites

```bash
# Repository/workflow contract tests
npm test

# .NET backend and backend-layer tests
DOTNET_CLI_HOME=/tmp/voxa-dotnet dotnet test backend/Voxa.sln --verbosity minimal

# Swift package tests on the macOS host
swift test --package-path ios/VoxaApp
```

For a simulator build and hosted app tests:

```bash
xcodebuild -project ios/Voxa.xcodeproj -scheme Voxa \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build CODE_SIGNING_ALLOWED=NO

xcodebuild -project ios/Voxa.xcodeproj -scheme Voxa \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test CODE_SIGNING_ALLOWED=NO
```

The exact simulator name is local to the installed Xcode version. Simulator
builds do not need signing; device and TestFlight builds do.

## iOS development

The committed [`ios/Voxa.xcodeproj`](ios/Voxa.xcodeproj) is generated from
[`ios/project.yml`](ios/project.yml). After changing the project specification:

```bash
cd ios
xcodegen generate
```

The Swift package is split into focused modules:

- `VoxaAppShell` — adaptive navigation and route gating.
- `VoxaAuth` — Sign in with Apple, session lifecycle, and Keychain storage.
- `VoxaOnboarding` — resumable onboarding and placement.
- `VoxaRealtime` / `VoxaRealtimeWebRTC` — voice session state and WebRTC.
- `VoxaHome` — profile-derived Today/Home surface.
- `VoxaPractice` — guided practice and translation tools.
- `VoxaProfiles` — language profile and settings flows.
- `VoxaDomain`, `VoxaNetworking`, `VoxaPersistence` — stable domain, HTTP,
  and persistence boundaries.

WebRTC is pinned in `ios/VoxaApp/Package.swift`; it is isolated behind the
realtime transport boundary and is not required by non-realtime domain tests.

For local backend/device testing, copy the ignored configuration template and
set a real URL:

```bash
cp ios/Voxa/Config/Debug.local.xcconfig.example \
   ios/Voxa/Config/Debug.local.xcconfig
# Edit Debug.local.xcconfig and set VOXA_API_BASE_URL and, for a signed device,
# DEVELOPMENT_TEAM.
```

`VOXA_PRIVACY_POLICY_URL` can also be set there for debug builds. Do not commit
the local file or real credentials.

## Backend development

The backend is a .NET modular monolith hosted by Azure Functions Flex
Consumption:

- `Voxa.Domain` contains identifiers, learner state, and domain exceptions.
- `Voxa.Application` contains use cases, ports, and mobile DTO contracts.
- `Voxa.Infrastructure` contains persistence and external-service adapters.
- `Voxa.Api` contains HTTP endpoints, validation, error responses, and
  configuration checks.

Run the API locally with the SDK selected by `global.json`:

```bash
dotnet run --project backend/src/Voxa.Api/Voxa.Api.csproj
```

The backend's mobile contract uses `/api` as its base path and includes:

- Apple authentication, refresh, and logout.
- Session resume and onboarding.
- Language-profile listing and active-profile selection.
- Realtime session credential issuance.
- Practice language tools, course/lesson planning, correction, and debrief.
- Account export and deletion.
- Development-only learner-state reset when explicitly enabled.

See [`docs/api-contracts.md`](docs/api-contracts.md) for request/response
shapes, correlation IDs, idempotency, concurrency, and retry rules. Azure
resources are not required for the unit-test suite; local integration testing
must use approved configuration and never embed production secrets.

## Azure infrastructure

Infrastructure is defined in Bicep and is intentionally split between a
workload resource group and a dedicated network resource group. The baseline
contains Azure Functions, private runtime storage, separate deployment-artifact
storage, Key Vault, managed identity/RBAC, VNet/private endpoints/private DNS,
Application Insights, and Log Analytics. Cosmos DB is optional and disabled by
default.

Local lint-only validation:

```bash
AZURE_CONFIG_DIR=/tmp/voxa-azure \
  ./infrastructure/scripts/validate.sh dev --lint-only
```

Azure-authenticated what-if validation:

```bash
az login
AZURE_CONFIG_DIR=/tmp/voxa-azure \
  ./infrastructure/scripts/validate.sh dev --what-if
```

Normal workload deployment is performed by GitHub Actions after merge to
`main`. One-time OIDC/bootstrap instructions, required repository secrets, and
resource-group safety notes are in [`infrastructure/README.md`](infrastructure/README.md).

For a branch-specific deployed test environment, use
[`docs/feature-branch-testing.md`](docs/feature-branch-testing.md). A branch
federated credential is separate from deployment; infrastructure only needs
redeployment when Bicep/bootstrap or that credential changes.

## CI, release, and TestFlight flow

### Pull requests

Pull requests run the repository checks and review automation. Backend, iOS,
and infrastructure validation workflows use path filters, with shared contract
files and workflow changes treated as cross-cutting. Releasable changes must
include a Changeset:

```md
---
"voxa": patch
---

Describe the user-facing or operational change.
```

See [`.changeset/README.md`](.changeset/README.md) for bump guidance.

### Main-branch validation

After merge, `CI` always validates the repository. `Backend CI`, `iOS CI`, and
the Azure workflows run when their path filters match. This keeps unrelated
commits cheap while ensuring API-contract and workflow changes fan out to the
dependent checks.

### Release

`Release` is triggered by completed validation workflows (`workflow_run`). It
checks the exact completed commit, waits for the required workflow conclusions,
computes changed files safely, consumes pending Changesets, and creates the
next version tag and GitHub release. A commit without a releasable Changeset
can legitimately result in no release.

### TestFlight

`iOS TestFlight` runs from the release/tag path or by manual dispatch. It checks
out the exact release commit, validates the Xcode project and scheme, signs
with Fastlane match, and uploads through App Store Connect. The workflow skips
the upload when the project or required signing/App Store Connect secrets are
not configured; a skipped run is not a successful binary delivery.

Detailed setup is in [`docs/testflight-setup.md`](docs/testflight-setup.md).

## Privacy, security, and App Store readiness

The engineering baseline covers Keychain token storage, backend-only permanent
OpenAI keys, short-lived realtime credentials, tenant/user scoping, Azure
managed identity, private data-plane resources, account export/deletion APIs,
and the iOS privacy manifest. It is not legal advice and does not replace
App Store Connect declarations or legal approval.

Before public release, reconcile runtime behavior with:

- [`docs/privacy-security-assurance.md`](docs/privacy-security-assurance.md)
- [`docs/app-store-privacy-checklist.md`](docs/app-store-privacy-checklist.md)
- [`docs/app-store-submission-package.md`](docs/app-store-submission-package.md)
- The published privacy policy URL configured as `VOXA_PRIVACY_POLICY_URL`

In particular, verify data-retention behavior against deployed Azure storage,
complete App Store Connect privacy answers, configure production signing, and
run physical-device/TestFlight acceptance testing.

## AI prompts and evaluations

Prompt behavior is versioned and reviewed. Runtime prompt files live under
`backend/prompts/`; design-facing conventions and examples live in
[`docs/prompts/README.md`](docs/prompts/README.md). Behavioral changes require
an immutable prompt version bump and a link to the governing specification.

Deterministic AI evaluation cases live in [`docs/evals/`](docs/evals/). They
cover correction, onboarding, routing, output shape, and policy-sensitive
behavior without relying on uncontrolled randomness.

## Development workflow

Use a dedicated branch and worktree for each coherent change, with worktrees
kept under the repository's `.worktrees/` directory. Sync `main` before
branching, keep one intent per pull request, use Conventional Commit messages,
and do not commit directly to `main`.

Pull requests should include the behavior changed, tests run, operational or
security impact, screenshots for meaningful iOS UI changes, and a Changeset
when the change is releasable. See [`docs/engineering-guidelines.md`](docs/engineering-guidelines.md)
for the repository's full engineering, security, infrastructure, and review
rules.

## Troubleshooting

| Symptom | First checks |
| --- | --- |
| .NET build uses the wrong SDK | Install .NET 10 and check `global.json`; run `dotnet --info`. |
| iOS project differs after editing the spec | Run `cd ios && xcodegen generate`, then commit the generated project. |
| Device build cannot sign | Configure `DEVELOPMENT_TEAM` and Apple capabilities; simulator builds can use `CODE_SIGNING_ALLOWED=NO`. |
| App cannot call the backend locally | Set `VOXA_API_BASE_URL` in ignored `Debug.local.xcconfig` and verify the deployed/local `/api` base URL. |
| TestFlight is skipped | Check for a release tag, project/scheme detection, and every secret in `docs/testflight-setup.md`. |
| Release is skipped | Confirm a pending `.changeset/*.md` file exists and required validation workflows completed for the same SHA. |
| Azure validation fails locally | Use a separate `AZURE_CONFIG_DIR`, authenticate with Azure CLI for what-if, and inspect Bicep diagnostics. |
| Realtime tests fail after dependency updates | Resolve Swift package caches and confirm the pinned WebRTC version before changing application code. |

## Further reading

- [Backend README](backend/README.md)
- [iOS README](ios/README.md)
- [Infrastructure README](infrastructure/README.md)
- [API contracts](docs/api-contracts.md)
- [TestFlight setup](docs/testflight-setup.md)
- [Feature-branch testing](docs/feature-branch-testing.md)
- [Privacy and security assurance](docs/privacy-security-assurance.md)
- [Engineering guidelines](docs/engineering-guidelines.md)

