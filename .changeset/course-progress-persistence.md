---
"voxa": patch
---

Adaptive curriculum arc, follow-on (C3.1): three targeted fixes to the personalised-course experience surfaced on-device.

**Lesson advancement persists to state.** Completing a `guided_lesson` session now advances the learner's `ActiveLearningPlan.Lessons` — the current PlannedLesson flips to `Completed` and the earliest non-completed lesson becomes `Current`. The Home course card refreshes on session end (existing wire), so "Lesson 4 of 28" moves forward when the learner actually finishes a lesson. Out-of-order completion (learner completes a Pending lesson while a different one is Current) marks the target Completed but leaves the Current pointer on the still-earliest non-completed lesson — the arc never leapfrogs. When every lesson is Completed the plan has no Current at all and Home reads "N of N — course complete".

**Home cards read as distinct surfaces.** Renamed the Today card header from "Continue \<language\>" to "Today's practice" and dropped the duplicated active-plan and current-lesson labels — those were echoing the Course card above it and made the two read like competing versions of the same thing. Today is now clearly "how much have I practised?" and the Course card is clearly "which lesson next?". Course card progress caption now includes completed count ("Lesson 4 of 28 · 3 done") so progress is visible after each session.

**Deleting every language reaches onboarding.** If a learner deleted their last language profile, `OnboardingGate` still short-circuited to `mainShell` because the local onboarding draft's `isCompleted` was true from that session's earlier submit. Home then rendered its "Let's set up your learning" placeholder with no way forward. Now the profile-flow's `.needsOnboarding` branch resets the onboarding draft on appear so the gate re-enters onboarding cleanly.
