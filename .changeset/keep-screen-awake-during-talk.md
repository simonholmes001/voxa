---
"voxa": patch
---

Keep the iPhone screen on during a Talk session. iOS auto-locks after ~30 s of no touches, and a live tutor session receives no touch events — so mid-session the device would sleep, drop the WebSocket, and cut the tutor off. `TalkSessionViewModel` now claims the platform "keep awake" lock (`UIApplication.isIdleTimerDisabled = true`) when the session reaches `.connected`, and releases it when `end()` runs. Injected through a new `IdleTimerControl` abstraction so the view model stays testable on non-UIKit hosts; a `RecordingIdleTimerControl` test double locks the behaviour under six new tests (kept-awake claim on connect, released on end, no claim if permission/connect fails, safe idempotent release from idle).
