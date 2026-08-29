import SwiftUI

/// The Voxa iPhone and iPad application entry point.
///
/// The entry point is intentionally thin: it hosts the adaptive root view
/// provided by `AppComposition`, which the app shell renders as a tab bar on
/// compact width (iPhone) or a split view on regular width (iPad).
@main
struct VoxaApp: App {
    var body: some Scene {
        WindowGroup {
            AppComposition.makeRootView()
        }
    }
}
