# App Store Submission Package

Status: draft release package for issue #123.
Last reviewed: 2026-09-16.

This package turns the privacy/security baseline into the concrete material
needed for App Store Connect and App Review. It must be reconciled with the
final published privacy policy URL before submission.

## Release Configuration Gate

App Store and TestFlight release builds must provide:

- `VOXA_API_BASE_URL`
- `VOXA_PRIVACY_POLICY_URL`

The TestFlight workflow fails before signing/upload when either value is
missing or is not an absolute HTTP(S) URL. Placeholder values are rejected by
the release-configuration validation step. `VOXA_PRIVACY_POLICY_URL` is
injected into `Info.plist` and used by the in-app Privacy policy row in More >
Languages. The validator does not replace the required public-link and legal
review checks below.

## App Store Connect App Privacy Answers

Use these answers as the current engineering inventory. Final answers still
need owner/legal review.

| Apple Data Category | Collected | Linked to User | Tracking | Purpose |
| --- | --- | --- | --- | --- |
| User ID | Yes | Yes | No | App functionality, product personalization |
| Other User Content | Yes | Yes | No | App functionality, product personalization |
| Audio Data | Yes | Yes | No | App functionality, product personalization |
| Photos or Videos | Yes | Yes | No | App functionality |
| Product Interaction | Yes | Yes | No | App functionality, product personalization |
| Other Diagnostic Data | Yes | Yes | No | App functionality, analytics |

Do not select third-party advertising, developer advertising, or tracking
purposes for the current app behavior.

## App Review Notes

Suggested reviewer notes:

Voxa requires Sign in with Apple so language profiles, course progress, account
export, and account deletion can be tied to the learner's app session. The app
uses the microphone and speech recognition only when the learner starts a voice
tutor, Ask by voice, or Translate by voice flow. Camera and photo access are
used only when the learner chooses image translation. Notifications are used
for a daily learning reminder after the learner grants permission.

AI tutoring, translations, lesson generation, and debrief summaries are
processed by backend services that call OpenAI. Permanent OpenAI API keys are
not included in the iOS app. The device receives short-lived Realtime client
credentials only after authenticated backend validation and rate/budget checks.

The Privacy policy, Export my data, and Delete account controls are available
in More > Languages. Delete account removes learner state, refresh sessions,
Realtime audit rows, and Realtime rate-limit rows for the authenticated user.

## Required Verification Before Submission

- Publish the final privacy policy and configure `VOXA_PRIVACY_POLICY_URL` in
  GitHub Actions variables or secrets for release builds.
- Open the distributed build and verify the Privacy policy row opens that URL.
- Complete App Store Connect App Privacy answers from this package and
  `docs/app-store-privacy-checklist.md`.
- Generate Xcode's privacy report and reconcile it with
  `ios/VoxaApp/PrivacyInfo.xcprivacy`.
- Verify account export and deletion against the deployed production storage
  account.
- Confirm microphone, speech recognition, camera/photo, and notification
  prompts are contextual and match the final privacy policy.

## Residual Risks To Accept Or Fix

- The final legal privacy policy is not stored in this repository as a
  published URL.
- Retention periods for learner state, generated content, audit rows, and logs
  are documented as engineering intent but still need operational validation.
- OpenAI and Azure processor/subprocessor records need owner/legal sign-off.
