---
"voxa": minor
---

Add the iOS onboarding and placement flow (`VoxaOnboarding`): a short stepped questionnaire capturing target/native language, goal, and daily time; a deterministic CEFR placement estimate from a quick self-assessment; and resumable draft persistence. `RootView` now shows onboarding after sign-in until it is complete. Backend profile storage and cross-device resume stay behind an injectable `OnboardingService` seam (owned by #20 backend / #14).
