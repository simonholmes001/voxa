---
"voxa": patch
---

Fix the post-sign-in "Loading your languages…" / "Please sign in again" failure on device, where every authenticated request lost its access token (backend 401) even though sign-in succeeded and the auth gate showed signed-in.

Root cause: `VoxaApp` built its composition inside the `WindowGroup` content closure (`AppComposition.makeRootView()`), which SwiftUI re-evaluates on every render. `makeRootView()` is a factory that creates fresh view models each call. `RootView` holds `authModel` in sticky `@State` (so the auth gate kept the original signed-in instance) but its child models (`profileModel`, etc.) as plain `let`, so a re-render rewired the profile service's token provider to a brand-new, signed-out `AuthViewModel` — hence `session == nil` and no token, permanently.

The app now builds the composed root exactly once by holding it in `@State`. The access-token provider is centralized in `AppComposition.accessTokenProvider(for:)` so every authenticated service reads the one shared `AuthViewModel`. Adds an app-target regression test asserting the provider is `nil` before sign-in and returns the session token after the shared model signs in.

Also hardens the profile load itself: `ProfileSelectionViewModel.load()` is single-flight and cancellation-safe (a cancelled SwiftUI `.task` can no longer discard the winning response, and the newest load always resolves to a terminal state), with an app-lifecycle trace (auth restore → scope → profile load) to pinpoint stalls on device.
