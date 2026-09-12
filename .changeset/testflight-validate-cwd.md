---
"voxa": patch
---

Fixes the `Xcode project not found` error from the TestFlight workflow's validation step.

`validate-ios-project.sh` was being invoked from the repo root while `VOXA_XCODE_PROJECT` was documented as ios-relative (`Voxa.xcodeproj`). From the repo root that path doesn't exist — the project is at `ios/Voxa.xcodeproj` — and the script exited with `Xcode project not found: ***`. Meanwhile the subsequent fastlane upload step correctly ran from `ios/`, so the same secret value would have worked there.

Fix: the validation step now also runs with `working-directory: ios`, matching the fastlane step. The script's default `MANIFEST_PATH` and `INFO_PLIST_PATH` are switched from `ios/…` to plain `…` so both invocations resolve from the same cwd. `docs/testflight-setup.md` updated to be explicit — `VOXA_XCODE_PROJECT = Voxa.xcodeproj` (no `ios/` prefix).

No secret changes required — after this merges, re-dispatch the workflow.
