---
"voxa": minor
---

Add an installable iPhone/iPad app target. `ios/Voxa.xcodeproj` (generated from `ios/project.yml` via XcodeGen) hosts `RootView` from the app shell, builds for iPhone and iPad simulators without Apple signing secrets, and ships a privacy manifest and microphone/speech usage strings. The TestFlight workflow now skips gracefully until signing secrets are configured.
