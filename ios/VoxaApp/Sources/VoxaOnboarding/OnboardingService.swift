import Foundation

/// Client-side seam for submitting the completed profile to the backend, which
/// stores it and seeds the first learning plan (#20 backend).
///
/// The wire contract is a backend responsibility (#14), so the default
/// implementation fails until a real client is injected.
public protocol OnboardingService: Sendable {
    func submit(_ profile: OnboardingProfile) async throws -> OnboardingProfile
    func resume() async throws -> OnboardingProfile?
}

public extension OnboardingService {
    func resumeCheckpoint() async throws -> OnboardingResumeCheckpoint? {
        guard let profile = try await resume() else { return nil }
        return OnboardingResumeCheckpoint(
            profile: profile,
            activePlan: nil,
            currentLesson: nil,
            reviewQueue: [],
            recentSessions: []
        )
    }
}

public struct OnboardingResumeCheckpoint: Sendable, Equatable {
    public var profile: OnboardingProfile
    public var activePlan: ActiveLearningPlan?
    public var currentLesson: LessonCheckpoint?
    public var reviewQueue: [ReviewQueueItem]
    public var recentSessions: [SessionSummary]

    public init(
        profile: OnboardingProfile,
        activePlan: ActiveLearningPlan?,
        currentLesson: LessonCheckpoint?,
        reviewQueue: [ReviewQueueItem],
        recentSessions: [SessionSummary]
    ) {
        self.profile = profile
        self.activePlan = activePlan
        self.currentLesson = currentLesson
        self.reviewQueue = reviewQueue
        self.recentSessions = recentSessions
    }
}

public struct ActiveLearningPlan: Sendable, Equatable {
    public var planId: String
    public var title: String
    public var knowledgeUnitIds: [String]

    public init(planId: String, title: String, knowledgeUnitIds: [String]) {
        self.planId = planId
        self.title = title
        self.knowledgeUnitIds = knowledgeUnitIds
    }
}

public struct LessonCheckpoint: Sendable, Equatable {
    public var lessonId: String
    public var knowledgeUnitId: String
    public var stepIndex: Int
    public var updatedAt: Date

    public init(lessonId: String, knowledgeUnitId: String, stepIndex: Int, updatedAt: Date) {
        self.lessonId = lessonId
        self.knowledgeUnitId = knowledgeUnitId
        self.stepIndex = stepIndex
        self.updatedAt = updatedAt
    }
}

public struct ReviewQueueItem: Sendable, Equatable {
    public var knowledgeUnitId: String
    public var dueAt: Date
    public var priority: Int

    public init(knowledgeUnitId: String, dueAt: Date, priority: Int) {
        self.knowledgeUnitId = knowledgeUnitId
        self.dueAt = dueAt
        self.priority = priority
    }
}

public struct SessionSummary: Sendable, Equatable {
    public var sessionId: String
    public var startedAt: Date
    public var durationSeconds: Int
    public var lessonId: String?

    public init(sessionId: String, startedAt: Date, durationSeconds: Int, lessonId: String?) {
        self.sessionId = sessionId
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.lessonId = lessonId
    }
}

public enum OnboardingServiceError: Error, Equatable {
    case unavailable
    case notFound
    case transportUnavailable
    case authenticationRequired
    case invalidResponse
    case serverUnavailable
}

/// Default service until the backend `/api/onboarding` client is wired
/// (tracked as a follow-up issue). It completes onboarding locally without a
/// network call, so first-run onboarding is not blocked on the backend.
public struct LocalOnboardingService: OnboardingService {
    public init() {}

    public func submit(_ profile: OnboardingProfile) async throws -> OnboardingProfile { profile }

    public func resume() async throws -> OnboardingProfile? {
        return nil
    }
}

/// Service that always fails, useful for tests that assert failure handling.
public struct UnavailableOnboardingService: OnboardingService {
    public init() {}

    public func submit(_ profile: OnboardingProfile) async throws -> OnboardingProfile {
        throw OnboardingServiceError.unavailable
    }

    public func resume() async throws -> OnboardingProfile? {
        throw OnboardingServiceError.unavailable
    }
}
