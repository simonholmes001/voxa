---
"voxa": minor
---

Add the iOS Talk-screen Realtime session client (`VoxaRealtime`): microphone permission handling, a connection lifecycle state machine (idle, requesting session, connecting, connected, failed, ended), and `TalkView`. The authenticated `POST /api/realtime/session` client (`VoxaBackendRealtimeSessionService`) fetches a short-lived credential; the WebRTC media transport is behind a `RealtimeTransport` seam (placeholder until the libwebrtc dependency is approved).
