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

    public init(languageName: String, levelName: String, goalName: String, dailyMinutes: Int) {
        self.languageName = languageName
        self.levelName = levelName
        self.goalName = goalName
        self.dailyMinutes = dailyMinutes
    }
}
