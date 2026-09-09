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
    /// Full second count for today's practice. Kept alongside
    /// `minutesPracticedToday` (which truncates to an integer minute) so the
    /// Home progress line can surface sub-minute sessions as "30 sec today"
    /// or "< 1 min today" instead of misleadingly rounding to 0.
    public var secondsPracticedToday: Int

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
        minutesPracticedToday: Int = 0,
        secondsPracticedToday: Int = 0
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
        self.secondsPracticedToday = secondsPracticedToday
    }

    public var dailyProgressFraction: Double {
        guard dailyMinutes > 0 else { return 0 }
        // Uses seconds so a 30-second session still moves the bar, even
        // though the label rounds to whole minutes.
        let secondsGoal = Double(dailyMinutes) * 60
        return min(1, Double(secondsPracticedToday) / secondsGoal)
    }

    /// Presentation-ready string for the Home progress line. Below one
    /// minute we surface seconds so the label matches reality; from one
    /// minute onward we round to whole minutes.
    public var practicedTodayLabel: String {
        if secondsPracticedToday <= 0 { return "0 of \(dailyMinutes) minutes today" }
        if secondsPracticedToday < 60 {
            return "\(secondsPracticedToday) sec today (< 1 min)"
        }
        return "\(minutesPracticedToday) of \(dailyMinutes) minutes today"
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
