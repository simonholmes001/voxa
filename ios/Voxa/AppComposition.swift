import SwiftUI
import VoxaAppShell

/// Composition root for the Voxa app target.
///
/// Keeps app-level wiring in one testable place so the `@main` entry point
/// stays trivial. As authentication (#17) and onboarding (#20) land, their
/// gates are composed here rather than in the `App` struct.
enum AppComposition {
    /// Builds the adaptive root view hosted by the app's main window.
    @MainActor
    static func makeRootView() -> RootView {
        RootView()
    }
}
