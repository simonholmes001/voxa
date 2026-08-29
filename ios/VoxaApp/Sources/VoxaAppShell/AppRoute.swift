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
