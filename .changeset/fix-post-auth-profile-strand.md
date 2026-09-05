---
"voxa": patch
---

Fix the post-auth profile load stranding the UI on a spinner despite a successful backend response. `ProfileSelectionViewModel.load()` is now single-flight and cancellation-safe: it runs the request in an unstructured task so a cancelled SwiftUI `.task` can no longer discard the winning response, and the newest load always resolves to a terminal state (the previous stale-request guard could return without setting any state, leaving `.loading` forever). Adds regression tests that reproduce the triggering-task-cancelled and repeated-trigger races, plus an app-lifecycle trace (auth restore → scope → profile load) to pinpoint stalls on device.
