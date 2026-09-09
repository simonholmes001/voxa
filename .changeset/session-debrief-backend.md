---
"voxa": minor
---

Backend pipeline for post-session debrief. New `POST /api/realtime/debrief` endpoint accepts the completed Talk session's turn-by-turn transcript, resolves the `realtime-tutor/debrief.v1` prompt through `IPromptRegistry`, calls the AssessmentModel (currently `gpt-5.6-sol`, high reasoning) with `response_format: json_object`, parses the structured JSON, and returns a `SessionDebriefHttpResponse` (summary + up to 3 recurring mistakes + up to 5 useful phrases + up to 3 pronunciation notes + one recommended next drill with justification). Non-realtime, adds one Chat Completions call per session. `IDebriefService` is DI-registered and receives its own `HttpClient`. Groundwork for the iOS debrief view in B2b; no iOS changes yet.
