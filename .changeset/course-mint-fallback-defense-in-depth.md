---
"voxa": patch
---

Remediation for the fourth code-review finding on PR #111 — the synchronous onboarding mint is defended at both boundaries so no upstream failure can strand a first-run learner.

**Author boundary wraps upstream + parse failures.** `OpenAiCourseAuthorService.AuthorCourseAsync` now converts `HttpRequestException` (network / DNS / socket), `TaskCanceledException` from `HttpClient.Timeout` (with the caller CT NOT cancelled), and `JsonException` from `ReadFromJsonAsync` (malformed OpenAI envelope) into `CourseAuthorException`. Cooperative cancellation via the caller's `CancellationToken` still propagates as `OperationCanceledException` — the boundary never swallows caller-initiated cancels.

**Onboarding catches any surprise except cancellation.** `OnboardingService.TryMintInitialCourseAsync` now catches `Exception` (not just `CourseAuthorException`), guarded by a `when (cancellationToken.IsCancellationRequested)` filter that re-raises caller cancellation. So a rogue `InvalidOperationException` from a misconfigured router, a `JsonException` slipped past the boundary, or any other surprise on the critical first-run synchronous path lands the learner with the placeholder plan and Home's "Generate my course" recovery — never a 500 that aborts onboarding. The log line includes the failing exception type name so operators can distinguish the failure classes.

Tests: backend 236 → 243 (+7). At the author boundary: `HttpRequestException` → `CourseAuthorException`, `TaskCanceledException` (timeout) → `CourseAuthorException`, malformed envelope → `CourseAuthorException`, caller cancellation is not swallowed. At the onboarding boundary: `HttpRequestException` from author → placeholder, `InvalidOperationException` from author → placeholder, caller cancellation is not swallowed.
