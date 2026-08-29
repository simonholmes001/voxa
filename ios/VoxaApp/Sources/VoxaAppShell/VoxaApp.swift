#if os(iOS)
import SwiftUI

/// The Voxa iPhone and iPad application entry point.
///
/// The entry point is intentionally thin: it hosts the adaptive `RootView`,
/// which selects a tab bar or split-view layout based on the horizontal size
/// class. This is compiled only for iOS/iPadOS; the macOS test host builds the
/// package library without an app entry point.
@main
public struct VoxaApp: App {
    public init() {}

    public var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
#endif
