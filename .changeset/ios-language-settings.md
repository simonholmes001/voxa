---
"voxa": minor
---

Add per-language settings (#84): a `LanguageSettingsViewModel` and `LanguageSettingsView` let the learner edit the active language profile's native language, goals (multi + custom), daily minutes, and placement level, saving through the idempotent `POST /api/onboarding` endpoint using the profile `version` as an `If-Match` concurrency token (409 → conflict state). The "Reset first run" control is compiled out of normal builds (dev-only, `#if DEBUG`).
