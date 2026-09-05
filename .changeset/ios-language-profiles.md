---
"voxa": minor
---

Add the iOS multi-language profile flow (#79): after sign-in the app lists the learner's language profiles and routes to onboarding (zero), the profile (one), or a chooser (multiple) where the learner continues an existing language or adds another. Adds `VoxaProfiles` (models, `LanguageProfilesService` seam, `ProfileSelectionViewModel`, and a chooser view), the `VoxaBackendLanguageProfilesService` client for `GET /api/language-profiles` and `POST /api/language-profiles/{key}/select`, and canonical BCP-47 language keys in onboarding. Each language's progress is independent (per-language backend profiles); creating another language does not overwrite existing data.
