---
"voxa": patch
---

Split PR CI into cheap repository checks and backend/iOS sentinel workflows that only run expensive tests for relevant paths, and pin iOS WebRTC to a release whose package manifest references an available binary artifact.
