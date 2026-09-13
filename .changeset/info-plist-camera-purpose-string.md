---
"voxa": patch
---

Two fixes so TestFlight releases are actually automatic and Apple accepts the upload.

**Camera purpose string.** Apple's async post-upload validator rejected the first TestFlight build with **ITMS-90683 — Missing purpose string in Info.plist**. voxa never uses the camera, but the WebRTC library it links references `AVCaptureDevice` at the API level, and Apple requires a purpose string for any camera-touching linked code even when the app never calls it. The string added to `Info.plist` is honest — it explains voxa doesn't currently use the camera and the declaration is only there for WebRTC.

**Auto-trigger from Release.** The old tag-push trigger silently didn't fire after `release.yml` created the `v<semver>` tag: GitHub deliberately does not let workflows triggered by `GITHUB_TOKEN` pushes chain into other workflows (loop prevention). Switched to `workflow_run` — `ios-testflight.yml` now fires when the `Release` workflow completes successfully on `main`, exempt from that rule. Marketing version resolution reads the newest `v*` tag (already pushed by Release moments earlier). Manual dispatch stays available for hotfix re-uploads.

After merge, the flow is: merge a changeset PR → `release.yml` tags → `ios-testflight.yml` auto-runs → build appears in TestFlight ~15 min after Apple's async validation completes. No more manual clicks per release.
