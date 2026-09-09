---
"voxa": minor
---

Every Talk session now ends with a structured debrief screen. iOS captures the tutor's and learner's turns during the session (enabling Whisper input transcription on the WebSocket), and — after the session ends — POSTs the transcript to `POST /api/realtime/debrief`. The response renders as a summary card, up to three recurring mistakes (with severity chips), up to five useful phrases, up to three pronunciation notes, and a "recommended next drill" card that launches straight into the next session. Debrief failures show inline under the Talk view without blocking the next session start; preparing a new intent implicitly acknowledges a stale summary. `DebriefRecommendedDrill.intent` maps every snake_case backend intent back into a launchable `RealtimeTutorIntent`, with safe fallbacks for unknown intents and missing focus/scenario titles.
