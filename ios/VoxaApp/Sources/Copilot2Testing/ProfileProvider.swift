import Foundation

public struct LearnerProfile: Codable, Equatable {
    public var goal: String
    public var minutesPerDay: Int
    public var language: String
    public var proficiencyBand: String

    public init(goal: String = "general", minutesPerDay: Int = 15, language: String = "en-US", proficiencyBand: String = "A1-A2") {
        self.goal = goal
        self.minutesPerDay = minutesPerDay
        self.language = language
        self.proficiencyBand = proficiencyBand
    }
}

/// Protocol to abstract persisted/profile state so network wiring can remain isolated for TDD.
public protocol ProfileProvider {
    /// Returns the currently-known learner profile if any.
    func currentProfile() async throws -> LearnerProfile?

    /// Attempts to resume a cross-device session and returns the resumed profile/state.
    func resumeSession() async throws -> LearnerProfile?
}
