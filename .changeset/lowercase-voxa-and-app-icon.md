---
"voxa": patch
---

Brand: the product refers to itself as "voxa" (lowercase) everywhere the learner sees or hears it, and a first-cut wordmark app icon lands.

**Lowercase "voxa" everywhere the app names itself.** Simon's stated brand preference. Updated:

- **iOS Info.plist** — `CFBundleDisplayName` becomes `voxa` (label under the app icon), and the microphone + speech-recognition usage descriptions rephrase to "voxa uses…".
- **iOS user-visible copy** — welcome screens, sign-in header, onboarding "voxa is designing…" overlay, reassess-course sheet hint, Home navigation title, error messages ("We couldn't reach voxa…"), Progress-tab detail copy. Every place the app previously said "Voxa" now says "voxa".
- **Tutor persona (persona-base)** — the shared realtime-tutor persona fragment now opens with "You are voxa" plus an explicit instruction never to write or say "Voxa" with a capital V, so the tutor introduces itself in lowercase when a learner asks its name.
- **Every other prompt that names the product** — curriculum-planner author + today-plan, debrief v1 + v2, onboarding placement conversation, correction mode-fragment. All shifted to "voxa".

Code identifiers (module names like `VoxaHome`, `Voxa.Application` C# namespaces, bundle id `com.simonholmes.voxa`, Xcode project name, entitlements filename) stay as they are — those are technical, not self-references.

**App icon — wordmark concept.** New source SVG at `ios/design/voxa-app-icon.svg`: "voxa" in a rounded bold sans, centred on the app's blue-→-violet-→-coral gradient, off-white with a soft warm cast. 1024×1024 master, iOS corner radius baked in. `rsvg-convert -w 1024 …` renders the shippable PNG for `AppIcon.appiconset`.

Tests: backend 245/245, iOS 327/327 — unchanged, no assertions rode on the "Voxa"-cased strings.
