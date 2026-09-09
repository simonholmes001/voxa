---
"voxa": patch
---

Prevent a crash when the same `WebSocketRealtimeTransport` instance is reconnected (start → end → start on the same Talk session). Every `connect()` re-ran `engine.attach(player)`, and attaching an already-attached `AVAudioNode` raises an ObjC `NSInternalInconsistencyException` that Swift can't catch. The setup is now guarded by an idempotent `configureAudioPipelineIfNeeded()` — the graph is attached exactly once per transport instance, `disconnect()` leaves it in place, and further reconnects reuse it safely. Also clears the mic input converter on disconnect for a clean teardown.
