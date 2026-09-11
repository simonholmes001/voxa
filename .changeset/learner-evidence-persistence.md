---
"voxa": minor
---

Post-session debriefs are now written to durable learner state after every Talk session, so Phase C2's curriculum planner has accumulated evidence to plan against. `LearnerState` gains a `TutorEvidence` field carrying the last 20 debriefs (correlation id, timestamp, summary, recurring mistakes with severity, useful phrases, pronunciation notes, and the recommended next drill). `POST /api/realtime/debrief` calls the new `ILearnerEvidenceService` after generating each debrief; persistence uses optimistic-concurrency retry (same pattern as session completion) and is idempotent on correlation id so a retried POST doesn't double-append. Persistence failures are logged but non-fatal — the client still gets its debrief. Table Storage documents round-trip the new field, and legacy rows written before this change load with an empty `TutorEvidence`. No user-visible change yet (that lands in C2).
