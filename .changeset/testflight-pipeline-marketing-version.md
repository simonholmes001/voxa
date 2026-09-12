---
"voxa": patch
---

Ships the `main` → tag → TestFlight release pipeline end-to-end, plus the two Info.plist prerequisites Apple gates uploads on.

**Info.plist.** Adds `ITSAppUsesNonExemptEncryption = false` so App Store Connect stops asking the export-compliance question on every build. voxa AI uses only standard HTTPS/TLS — no non-exempt encryption to declare.

**Marketing version from changeset-driven tags.** Removes `increment_build_number` (which mutates `project.pbxproj`) from the fastlane lane. Instead the lane passes `CURRENT_PROJECT_VERSION` and `MARKETING_VERSION` to `gym` via `xcargs`, so the checkout stays clean. Marketing version comes from the git tag `release.yml` pushes (`v0.20.0` → `0.20.0`); build number comes from `github.run_number` (monotonic per workflow — guaranteed unique). If `VOXA_MARKETING_VERSION` is not set, the value in `ios/project.yml` (`0.1.0`) is used as a fallback so local `fastlane` runs still work.

**Workflow trigger model.** Changes `.github/workflows/ios-testflight.yml` from "push to main under `ios/**`" to:
1. **Tag push** (`v*`) — the steady state. `release.yml` creates the tag after a changeset-driven main merge; that tag push runs the TestFlight upload.
2. **Manual dispatch** — with an optional `marketing_version` input for hotfix re-uploads or the very first upload (before any `v*` tag exists).
The old push-to-main trigger raced with `release.yml` (the tag it creates would not yet exist when the upload started) and would upload even when there was nothing releasable — the tag model fixes both.

**Setup guide.** `docs/testflight-setup.md` walks through every one-time step: creating the private cert repo, initialising `match`, encoding the App Store Connect `.p8` key, minting the fine-grained PAT for `MATCH_GIT_BASIC_AUTHORIZATION`, and every GitHub Actions secret with its exact source. Includes a first-upload manual-dispatch path (because `main` has no `v*` tag yet), a steady-state release-driven path, and a troubleshooting section.
