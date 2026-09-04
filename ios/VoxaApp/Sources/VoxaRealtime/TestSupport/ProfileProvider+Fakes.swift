import Foundation

// Test-support types for Copilot2 TDD scaffolding — placed in VoxaRealtime so unit tests can import them.

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

public protocol ProfileProvider {
    func currentProfile() async throws -> LearnerProfile?
    func resumeSession() async throws -> LearnerProfile?
}

public final class FakeProfileProvider: ProfileProvider {
    public var profile: LearnerProfile?
    public var resumeResult: LearnerProfile?
    public var shouldThrowResume: Bool = false

    public init(profile: LearnerProfile? = nil, resumeResult: LearnerProfile? = nil, shouldThrowResume: Bool = false) {
        self.profile = profile
        self.resumeResult = resumeResult
        self.shouldThrowResume = shouldThrowResume
    }

    public func currentProfile() async throws -> LearnerProfile? {
        return profile
    }

    public func resumeSession() async throws -> LearnerProfile? {
        if shouldThrowResume {
            throw NSError(domain: "FakeProfileProvider", code: -1, userInfo: [NSLocalizedDescriptionKey: "simulated resume failure"])
        }
        try? await Task.sleep(nanoseconds: 30_000_000)
        return resumeResult
    }
}
