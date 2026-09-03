/// The primary top-level destinations of the Voxa app.
///
/// These map directly to the navigation surfaces required by the MVP:
/// Home, Talk, Learn, Review, Progress, and Settings. The order is the
/// canonical order used by both the iPhone tab bar and the iPad sidebar.
public enum AppRoute: String, CaseIterable, Identifiable, Hashable, Sendable {
    case home
    case talk
    case learn
    case review
    case progress
    case settings

    public var id: String { rawValue }

    /// Human-readable label shown in tab items and sidebar rows.
    public var title: String {
        switch self {
        case .home: return "Home"
        case .talk: return "Talk"
        case .learn: return "Learn"
        case .review: return "Review"
        case .progress: return "Progress"
        case .settings: return "Settings"
        }
    }

    /// SF Symbol name used for the route's tab item and sidebar row.
    public var systemImageName: String {
        switch self {
        case .home: return "house"
        case .talk: return "waveform"
        case .learn: return "book"
        case .review: return "arrow.triangle.2.circlepath"
        case .progress: return "chart.bar"
        case .settings: return "gearshape"
        }
    }
}

/// Lightweight struct describing the placeholder content shown for routes
/// that don't yet have full feature implementations. This keeps UI placeholder
/// text meaningful and testable without rendering SwiftUI views in unit tests.
public struct RoutePlaceholderContent: Sendable, Equatable {
    public let headline: String
    public let subheadline: String
    public let actionTitle: String?

    public init(headline: String, subheadline: String, actionTitle: String? = nil) {
        self.headline = headline
        self.subheadline = subheadline
        self.actionTitle = actionTitle
    }
}

public extension AppRoute {
    /// Returns purposeful placeholder content for device testing and demos.
    /// These are intentionally minimal but descriptive so testers can exercise
    /// each tab and verify navigation/state without the full feature.
    func placeholderContent() -> RoutePlaceholderContent {
        switch self {
        case .learn:
            return RoutePlaceholderContent(
                headline: "Learn",
                subheadline: "Start a short lesson to practice vocabulary and grammar.",
                actionTitle: "Start Lesson"
            )
        case .review:
            return RoutePlaceholderContent(
                headline: "Review",
                subheadline: "Practice quick review sessions tailored to your recent lessons.",
                actionTitle: "Start Review"
            )
        case .settings:
            return RoutePlaceholderContent(
                headline: "More",
                subheadline: "Manage account, preferences, and app settings.",
                actionTitle: "Open Settings"
            )
        default:
            return RoutePlaceholderContent(
                headline: title,
                subheadline: "Coming soon",
                actionTitle: nil
            )
        }
    }
}
