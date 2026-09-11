---
"voxa": minor
---

Fixes two on-device bugs Simon reported in guided lessons.

**Bilingual scaffolding for beginners (Bucket D).** A brand-new A1 learner starting a lesson had no idea what was going on because the tutor opened straight in the target language. Guided-lesson prompt bumped to v2 with a mandatory L1 opener: one sentence in the learner's native language naming the lesson topic and what they'll be able to *do* by the end, one sentence previewing the target structure, then a switch to the target language. B1+ still opens directly in the target language. A brief L1 gloss is permitted during the target-introduction step at A1/A2.

**Lesson actually ends (Bucket B).** The tutor was looping "Say your name is X" over and over even after the learner responded. Guided-lesson v2 adds a mandatory anti-loop rule ("MUST NOT repeat the same prompt more than once — if the learner has responded at all, MOVE ON") and a mandatory bounded end-of-lesson closure: after the learner produces the target structure twice, the tutor delivers a one-sentence L1 congratulation, then a target-language closing phrase plus the exact marker `Session complete.`, then stops. If the learner speaks after that, the tutor confirms once in L1 that the lesson is done and waits silently.

The `nativeLanguage` variable is threaded end-to-end: added to `RealtimeSessionCommand` / `RealtimeSessionSettingsContract` (optional for wire-compat), the `POST /api/realtime/session` request DTO, iOS `RealtimeCoachingSettings`, and the request DTO in `VoxaNetworking`. `AppComposition.realtimeSettings` populates it from the learner's onboarding profile, title-cased via the existing `LanguageDisplayName` helper. When the client doesn't send it (legacy or offline), the backend falls back to `"English"` at render time so the session still succeeds — just with degraded L1 scaffolding.

Tests: backend 243 → 245 (+2 prompt-render assertions covering the anti-loop guarantee, the "Session complete" marker, and the English fallback). iOS 327/327. Existing tests updated for the new `nativeLanguage` field on the wire contracts.
