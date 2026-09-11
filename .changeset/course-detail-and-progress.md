---
"voxa": minor
---

Curriculum visibility and multi-language ergonomics (Bucket E of the local-testing follow-up).

**Full syllabus visible.** New `CourseDetailView` shows every lesson in the arc — past (✓), current (▶ highlighted), upcoming (○) — with the title, learning objective and estimated minutes for each. Reached from the Home course card ("See all N lessons") and from the Progress tab ("See lesson plan"). Every row is tappable: current starts the lesson, completed offers to redo, upcoming starts a fresh guided lesson for that topic (the backend's out-of-order handling in `LearningSessionCompletionService` makes non-linear completion safe — the arc's Current pointer never leapfrogs). The reassess button lives inside the sheet too, so the reshape affordance stays reachable while browsing.

**Progress tab reads real data.** Was a static `LearningRouteView` placeholder. Now `ProgressDashboardView` renders course completion (X of Y lessons + progress bar), today's practice minutes (against the daily target), due-review count, recent-session count, and a "Start this lesson" CTA for the current lesson. Data comes from `LearnerCourse` + `LearnerProfileSummary` — nothing new to load. A local `ProgressRoute` in `VoxaAppShell` owns the CourseDetailView sheet state so tapping "See lesson plan" opens the arc without bouncing back to Home.

**Compact language chips at 3+.** Home's "Your languages" list stayed vertical no matter how many languages you had — three languages pushed the course card off-screen on smaller devices. Now with 2 or fewer languages it stays a vertical list (unchanged), and at 3+ it collapses into a horizontal scrolling chip row so the course card and Today card stay above the fold.

Shared `LearnerCourse.progressCaption` extracted to remove the copy-paste of "Lesson N of M · X done" across Home, Progress and CourseDetail. +6 unit tests for the extraction plus `completedLessonCount`.

Backend tests: 227/227. iOS tests: 321/321 (315 → 321).
