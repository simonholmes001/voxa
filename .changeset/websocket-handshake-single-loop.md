---
"voxa": patch
---

Fix the WebSocket Realtime transport so early server events between `session.created` and `session.updated` are no longer dropped. The receive loop now starts before any handshake step, and handshake waiters register interest via a per-event continuation dispatcher instead of consuming the socket directly. Also fails any pending handshake waiter when the socket closes or errors out, so failed connects no longer hang until their 10-second timeout.
