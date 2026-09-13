---
"voxa": patch
---

Two fixes so TestFlight releases are actually automatic and Apple accepts the upload.

**Camera purpose string.** Apple's async post-upload validator rejected the first TestFlight build with **ITMS-90683 — Missing purpose string in Info.plist**. voxa never uses the camera, but the WebRTC library it links references `AVCaptureDevice` at the API level, and Apple requires a purpose string for any camera-touching linked code even when the app never calls it. The string added to `Info.plist` is honest — it explains voxa doesn't currently use the camera and the declaration is only there for WebRTC.

**Auto-trigger from Release.** The old tag-push trigger silently didn't fire after `release.yml` created the `v<semver>` tag: GitHub deliberately does not let workflows triggered by `GITHUB_TOKEN` pushes chain into other workflows (loop prevention). Switched to `workflow_run` — `ios-testflight.yml` now fires when the `Release` workflow completes successfully on `main`, exempt from that rule. Marketing version resolution binds to `github.event.workflow_run.head_sha` — the exact commit Release ran against — via `git tag --points-at`, so a concurrent unrelated tag can't leak the wrong version into the upload (High-severity finding from the PR review, fixed in the same PR). Checkout is also pinned to that commit so the archive is byte-identical to what Release blessed. If no v\* tag points at head_sha, the job fails loudly rather than guessing. Manual dispatch stays available for hotfix re-uploads.

After merge, the flow is: merge a changeset PR → `release.yml` tags → `ios-testflight.yml` auto-runs → build appears in TestFlight ~15 min after Apple's async validation completes. No more manual clicks per release.
