---
"voxa": minor
---

Improve onboarding language and goal inputs (#80): target/native language lists are now shown alphabetically (presentation-only; stored values unchanged), and goals are multi-select with support for custom goals (trimmed, non-empty, ≤ 40 chars, de-duplicated, up to 5). Onboarding now models `goals` as an array end-to-end (`OnboardingProfile.goals: [String]`) and submits `goals` as an array to `POST /api/onboarding`.
