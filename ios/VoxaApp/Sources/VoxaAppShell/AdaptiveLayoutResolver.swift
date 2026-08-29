/// A platform-agnostic representation of a horizontal size class.
///
/// This mirrors UIKit/SwiftUI's horizontal size class but carries no framework
/// dependency, so the adaptive layout decision can be unit tested on any host.
public enum InterfaceSizeClass: Sendable, Equatable {
    case compact
    case regular
}

/// The navigation container style the app shell should present.
public enum NavigationLayout: Sendable, Equatable {
    /// Bottom tab bar, used for compact width (typically iPhone portrait).
    case tabBar
    /// Sidebar/split view, used for regular width (typically iPad and large
    /// iPhones in landscape).
    case splitView
}

/// Resolves which navigation container the app shell should use for a given
/// horizontal size class.
///
/// A regular width earns the richer split/sidebar layout; compact width (or an
/// unknown size class) falls back to the tab bar so navigation is always
/// available.
public enum AdaptiveLayoutResolver {
    public static func layout(for horizontalSizeClass: InterfaceSizeClass?) -> NavigationLayout {
        switch horizontalSizeClass {
        case .regular:
            return .splitView
        case .compact, .none:
            return .tabBar
        }
    }
}
