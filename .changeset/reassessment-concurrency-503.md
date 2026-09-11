---
"voxa": patch
---

Remediation for the Medium code-review finding on PR #111.

**Reassessment concurrency exhaustion now returns a retryable 503.** `CourseReassessmentService.ReassessAsync` retries under optimistic concurrency but rethrows `StaleLearnerStateVersionException` on the final attempt. `CourseReassessmentEndpoint.PostAsync` only caught `LearnerStateNotFoundException` and `CourseAuthorException`, so an exhausted-conflict path escaped as an unhandled 500 — clients couldn't distinguish "transient conflict worth retrying" from a real server bug. The endpoint now maps `StaleLearnerStateVersionException` to a 503 with error code `course_reassessment_conflict` and `Retryable: true`, so client-side recovery is deterministic and telemetry can distinguish contended writes from other failures. +1 endpoint test covers the exhausted-conflict path end-to-end.
