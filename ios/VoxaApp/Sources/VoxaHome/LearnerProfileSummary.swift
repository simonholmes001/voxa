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
    public var activePlanTitle: String?
    public var currentLessonTitle: String?
    public var currentLessonStepIndex: Int?
    public var dueReviewCount: Int
    public var recentSessionCount: Int
    public var minutesPracticedToday: Int

    public init(
        languageName: String,
        levelName: String,
        goalName: String,
        dailyMinutes: Int,
        isStale: Bool = false,
        activePlanTitle: String? = nil,
        currentLessonTitle: String? = nil,
        currentLessonStepIndex: Int? = nil,
        dueReviewCount: Int = 0,
        recentSessionCount: Int = 0,
        minutesPracticedToday: Int = 0
    ) {
        self.languageName = languageName
        self.levelName = levelName
        self.goalName = goalName
        self.dailyMinutes = dailyMinutes
        self.isStale = isStale
        self.activePlanTitle = activePlanTitle
        self.currentLessonTitle = currentLessonTitle
        self.currentLessonStepIndex = currentLessonStepIndex
        self.dueReviewCount = dueReviewCount
        self.recentSessionCount = recentSessionCount
        self.minutesPracticedToday = minutesPracticedToday
    }

    public var dailyProgressFraction: Double {
        guard dailyMinutes > 0 else { return 0 }
        return min(1, Double(minutesPracticedToday) / Double(dailyMinutes))
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
