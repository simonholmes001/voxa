/// A display-ready summary of the learner's profile shown on the Home surface.
///
/// Kept as presentation-ready strings so `VoxaHome` does not depend on the
/// onboarding or networking modules; the app composition layer maps the source
/// profile into this value.
public struct LearnerProfileSummary: Sendable, Equatable {
    public var languageName: String
    public var levelName: String
    public var goalName: String
    public var dailyMinutes: Int
    public var isStale: Bool

    public init(
        languageName: String,
        levelName: String,
        goalName: String,
        dailyMinutes: Int,
        isStale: Bool = false
    ) {
        self.languageName = languageName
        self.levelName = levelName
        self.goalName = goalName
        self.dailyMinutes = dailyMinutes
        self.isStale = isStale
    }
}

/// Compact language row used by Home. This keeps the Home module independent
/// from the richer profile model owned by `VoxaProfiles`.
public struct LearnerLanguageSummary: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var levelName: String
    public var dailyMinutes: Int
    public var isActive: Bool

    public init(id: String, name: String, levelName: String, dailyMinutes: Int, isActive: Bool) {
        self.id = id
        self.name = name
        self.levelName = levelName
        self.dailyMinutes = dailyMinutes
        self.isActive = isActive
    }
}
