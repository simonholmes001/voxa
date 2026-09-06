---
"voxa": minor
---

Add an in-app Languages manager (More tab) so learners can run several courses in parallel.

- Remove the temporary "Reset first run" debug button from the UX.
- New `LanguageManagementView` in the More surface: list every language profile, mark and switch the active course, add a new language (a new parallel course), and sign out.
- Edit any existing language's parameters — native language, goals, daily minutes (incl. custom), and placement — reusing `LanguageSettingsView`, saved via `POST /api/onboarding` with the profile's `version` as the `If-Match` concurrency token. The target language is a course's identity, so changing course = Add Language rather than an in-place edit, preserving each language's independent progress.
- Adding a language from inside the app now works from any state (`RootView.profileFlow` short-circuits to the add flow) and refreshes the profile list on completion so a former single-language learner correctly becomes multi-language.
- `ProfileSelectionViewModel` exposes `allProfiles`, `hasProfiles`, and `refresh()`; the manager reads the single shared model. Adds view-model tests for the accessors, refresh, and parallel-course listing.
