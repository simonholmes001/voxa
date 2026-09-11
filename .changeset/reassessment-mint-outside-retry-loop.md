---
"voxa": patch
---

Remediation for the third code-review finding on PR #111.

**Reassessment now runs the OpenAI course-author call exactly once, outside the optimistic-concurrency retry loop.** Previously `CourseReassessmentService.ReassessAsync` re-invoked `courseAuthor.AuthorCourseAsync` from inside the retry `for` loop, so a stale-version conflict triggered a second (and potentially third) expensive, non-idempotent model call for a single learner request. That let one accepted plan get silently replaced by a different one before persistence, changed completed/current mapping between attempts, and multiplied upstream cost and latency under contention.

The service now reads state and mints the plan once. The retry loop only retries the SAVE — on a `StaleLearnerStateVersionException` it re-reads the fresher state, remaps the minted plan's lesson statuses locally against the fresh `CompletedLessonIds` (a purely-local `ApplyCompletionStatuses` pass), and retries the save. Result: whichever plan the first successful mint produced is what lands, contended or not; concurrent completions between mint and save still land as `Completed` in the final saved plan without a second author invocation.

Test coverage tightened: the retry test now asserts `authorInvocationCount == 1` after two stale-version conflicts, and a new test models a concurrent guided-lesson completion landing between mint and save — verifying the freshly-completed lesson id surfaces as `Completed` in the persisted plan without re-authoring.

Backend tests: 235 → 236 (+1 new coverage of the remap path; the retry test now also asserts the mint runs once).
