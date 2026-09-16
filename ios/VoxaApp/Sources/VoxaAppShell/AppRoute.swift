/// The primary top-level destinations of the Voxa app.
///
/// These map directly to the main navigation surfaces. The order is the
/// canonical order used by both the iPhone tab bar and the iPad sidebar.
public enum AppRoute: String, CaseIterable, Identifiable, Hashable, Sendable {
    case home
    case talk
    case tutor
    case practice
    case review
    case progress
    case settings

    public static let allCases: [AppRoute] = [.home, .talk, .practice, .review, .settings]

    public var id: String { rawValue }

    /// Human-readable label shown in tab items and sidebar rows.
    public var title: String {
        switch self {
        case .home: return "Home"
        case .talk: return "Talk"
        case .tutor: return "Tutor"
        case .practice: return "Practice"
        case .review: return "Review"
        case .progress: return "Progress"
        case .settings: return "More"
        }
    }

    /// SF Symbol name used for the route's tab item and sidebar row.
    public var systemImageName: String {
        switch self {
        case .home: return "house"
        case .talk: return "waveform"
        case .tutor: return "person.wave.2"
        case .practice: return "square.grid.2x2"
        case .review: return "arrow.triangle.2.circlepath"
        case .progress: return "chart.bar"
        case .settings: return "ellipsis"
        }
    }
}

/// Lightweight struct describing fallback route content when a destination is
/// rendered without its feature dependencies. This keeps copy meaningful and
/// testable without rendering SwiftUI views in unit tests.
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
    /// Returns purposeful fallback content for device testing and demos.
    func placeholderContent() -> RoutePlaceholderContent {
        switch self {
        case .tutor:
            return RoutePlaceholderContent(
                headline: "Tutor",
                subheadline: "Customize your AI tutor's voice, tone, speed, and speaking style.",
                actionTitle: nil
            )
        case .practice:
            return RoutePlaceholderContent(
                headline: "Practice",
                subheadline: "Pick an activity, or take today's recommended session — free conversation, a lesson, pronunciation, listening, or a scenario roleplay.",
                actionTitle: "Start talking"
            )
        case .review:
            return RoutePlaceholderContent(
                headline: "Review",
                subheadline: "Practice mistakes, weak words, and pronunciation notes from your tutor sessions.",
                actionTitle: "Review with Tutor"
            )
        case .settings:
            return RoutePlaceholderContent(
                headline: "More",
                subheadline: "Manage language profiles, goals, daily time, and tutor preferences.",
                actionTitle: "Add a Language"
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
