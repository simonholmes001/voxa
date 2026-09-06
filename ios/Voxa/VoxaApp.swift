import SwiftUI

/// The Voxa iPhone and iPad application entry point.
///
/// The entry point is intentionally thin: it hosts the adaptive root view
/// provided by `AppComposition`, which the app shell renders as a tab bar on
/// compact width (iPhone) or a split view on regular width (iPad).
@main
struct VoxaApp: App {
    /// Build the composition (auth, onboarding, profile, talk, home view models)
    /// exactly once. `makeRootView()` is a factory that instantiates fresh view
    /// models on every call, so it must never run inside the `WindowGroup`
    /// content closure — SwiftUI re-evaluates that closure on re-render, which
    /// would rewire `RootView`'s non-`@State` child models (e.g. `profileModel`)
    /// to a brand-new, signed-out `AuthViewModel` while the sticky `@State`
    /// `authModel` behind the auth gate stays signed in. That split is what left
    /// authenticated requests with no access token. Holding the composed root in
    /// `@State` pins a single, consistent set of models for the app's lifetime.
    @State private var root = AppComposition.makeRootView()

    var body: some Scene {
        WindowGroup {
            root
        }
    }
}
