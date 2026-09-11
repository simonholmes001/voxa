---
"voxa": patch
---

Follow-on to the adaptive-curriculum-arc branch (F1–F4) covering multi-language regressions found on-device.

**Language names render title-case everywhere.** Custom language names typed as free text during onboarding ("greek", "PORTUGUESE") no longer surface lowercase on Home, Progress, More/Languages, or the language chooser. New `LanguageDisplayName.titleCased` helper (in `VoxaProfiles`) applies `localizedCapitalized` and trims whitespace; called at every display site. Standard catalog languages ("de-DE" → "German") pass through unchanged.

**Course reloads on language switch.** Switching active language (via the Home languages card or the More/Languages screen) reloaded the profile and Home summary but not the `LearnerCourseViewModel`. The course card kept showing the previously-active language's arc until the app was relaunched — Simon's exact "I switched to German and lost my German lessons" symptom. Both `openSelectedProfile` and `activateSubmittedLanguage` in `RootView` now `await learnerCourseModel?.load()` and `learnerPlanModel?.load()` after activation.

**Zero-lesson recovery affordance.** Backend course-authoring can fail (rate limit, model timeout, unusual language input) and fall back to the placeholder plan with no lessons — the "Beginner Foundations · See all 0 lessons" state. The Home course card now detects `totalLessons == 0` and shows a prominent "Generate my course" call-to-action instead of a disabled see-all chip. Tapping opens the existing Reassess sheet pre-filled with a generation hint, so the learner is one tap from a working arc.

**Backend logs the mint failure.** `OnboardingService.TryMintInitialCourseAsync` previously swallowed `CourseAuthorException` silently. Added `Microsoft.Extensions.Logging.Abstractions` to `Voxa.Application` (abstractions-only — no implementation pulled in) and now logs the failure at Warning level with correlation id, target language, native language, and proficiency level so operators can diagnose which mints are failing and why on the next redeploy.

Backend tests: 227/227. iOS tests: 321 → 327 (+6 pure-model tests for `LanguageDisplayName`).
