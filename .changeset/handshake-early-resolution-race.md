---
"voxa": patch
---

Close a hang in the WebSocket Realtime handshake: if a matching server event (`session.created` / `session.updated`) landed in the receive loop after the waiter was published to the dispatcher but before its `CheckedContinuation` was attached, the resolve was silently lost and the caller stalled until the 10 s timeout. `HandshakeContinuation` now remembers terminal state and honours it on late `attach()`. The timeout task also throws so `waitForHandshakeEvent` can't return successfully when the timeout wins the group's completion race.
