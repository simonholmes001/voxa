---
"voxa": minor
---

Add the iOS Talk-screen Realtime **session client and UI only** (`VoxaRealtime`): microphone permission handling, a connection lifecycle state machine (idle, requesting session, connecting, connected, failed, ended), and `TalkView`. The authenticated `POST /api/realtime/session` client (`VoxaBackendRealtimeSessionService`) fetches a short-lived credential, and session settings (target language, proficiency band) are derived from onboarding state at start time. This does **not** include live audio: the WebRTC media transport is behind a `RealtimeTransport` seam (`UnavailableRealtimeTransport`) pending a separate libwebrtc dependency decision. The backend base URL is configured via `VOXA_API_BASE_URL` (Debug `Debug.local.xcconfig` for local/device testing).
