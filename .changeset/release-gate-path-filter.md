---
"voxa": patch
---

Fix release validation so it waits only for path-filtered CI workflows that GitHub schedules for the release commit, preventing iOS-only merges from timing out while waiting for Backend CI.
