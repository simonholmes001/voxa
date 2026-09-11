---
"voxa": minor
---

C2 of Phase C: the Practice Hub Today card now shows a per-learner recommendation instead of the rule-based rotation. New `GET /api/learner/plan` endpoint runs the `curriculum-planner/today-plan.v1` prompt (bound to `CurriculumModel`) over the learner's persisted evidence — active plan, current lesson, due reviews, and up to the last 20 debriefs written by C1 — and returns a recommended session (activity intent + focus + reason) plus up to three concrete focus areas. iOS `LearnerPlanViewModel` fetches on Practice tab appearance and re-fetches after every Talk session ends so a fresh debrief immediately shapes the next plan. Loading state shows a spinner next to the "TODAY" label; failure falls back cleanly to the B3 rule-based card so the learner never sees a blank surface.
