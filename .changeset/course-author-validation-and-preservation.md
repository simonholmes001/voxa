---
"voxa": patch
---

Remediation for the two code-review findings on PR #111.

**High — enforce the 20–30 lesson schema server-side.** The OpenAI call uses `response_format: json_object`, not `json_schema`, so the constraints declared in `curriculum-planner/author-course.v1.yaml` (`minItems: 20`, `maxItems: 30`, required title / learningObjective / order / estimatedMinutes) are documentation for the model, not an enforced envelope. Under-sized or otherwise malformed model responses could persist as the learner's real course. Added `ValidatePayloadOrThrow` in `OpenAiCourseAuthorService.AuthorCourseAsync`: rejects a payload whose kept-lesson count is outside `[20, 30]`, or whose lessons have a blank title / blank learningObjective / missing or duplicate `order` / `estimatedMinutes` outside `[5, 60]`. Throws `CourseAuthorException` so onboarding falls back to the placeholder plan (surfacing the "Generate my course" recovery card on Home) and reassessment returns retryable to the client.

**Medium — deterministic progress preservation across a re-mint.** `CourseAuthorPayload.ToActivePlan` matched titles case-insensitively but exact-string, so any punctuation or whitespace refinement to a completed lesson's title dropped the lesson id and silently regressed the learner's progress — even though the prompt explicitly permits "slightly refined" titles. Added `NormaliseTitleForMatch` (case-fold, strip non-alphanumerics, collapse whitespace) so "Ordering food, at a restaurant." matches "Ordering food at a restaurant". After the payload is turned into an `ActiveLearningPlan`, `EnsureCompletedLessonsPreservedOrThrow` verifies every `CompletedLessonIds` entry surfaces as `Completed` in the new plan; if any are missing the reassessment is refused with `CourseAuthorException` rather than persisted with silent progress loss.

Tests: backend 227 → 234 (+7). Five new negative-case tests around the schema gate (too few, too many, blank objective, duplicate order, out-of-range minutes), plus preservation tests for the punctuation-refinement regression and the drop-a-completed-lesson refusal path.
