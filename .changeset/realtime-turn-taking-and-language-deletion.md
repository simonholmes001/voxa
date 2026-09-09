---
"voxa": minor
---

Make the realtime tutor a real conversation and add language deletion.

Realtime tutor: audio is now audible on device (fixes the Float32 vs Int16 buffer-format mismatch that silently dropped playback, and switches `AVAudioSession` from `.voiceChat` — which capped output — to `.measurement`). Server-authoritative turn-taking via `create_response: false` + `interrupt_response: true` from the backend `client_secret` mint, a target-language handoff cue in the instructions ("À toi" / "Tu turno" / …), and four defensive layers on iOS (playback-anchored mic gate, gate-guarded `speech_stopped` handling, spurious-response cancellation, and a WebSocket `session.update` re-sending strict turn-detection as a JSON literal to avoid `JSONSerialization` rendering `Double` with 17+ decimal places). New tap-to-interrupt: the Talk screen's waveform icon becomes a plain button while `.connected` and calls a new `RealtimeTransport.interrupt()`, which stops the audio player, releases the mic gate, and sends `response.cancel`.

Language management: new `DELETE /api/language-profiles/{languageKey}` endpoint with `ILearnerStateRepository` deletion path (in-memory + Azure Table Storage), iOS `LanguageManagementView`, and profile-selection service wiring.
