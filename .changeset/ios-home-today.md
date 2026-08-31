---
"voxa": minor
---

Add the iOS Home/Today post-onboarding surface (`VoxaHome`): `HomeView` shows a profile summary (language, level, goal, daily minutes) and a Today/start card whose primary action routes into the Talk voice screen, usable on both iPhone and iPad. The profile is loaded from server learner state via `OnboardingService.resume()` with a local onboarding-profile fallback when offline, handling loading/ready/new-user/error states. This is the minimum post-onboarding flow; next lesson, due review, and recent progress remain part of the broader #28.
