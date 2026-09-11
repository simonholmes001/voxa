import Foundation

/// The result of C2's curriculum planner: one recommended next session
/// plus up to three concrete focus areas the learner sees as chips on the
/// Home Today card. Shape mirrors the backend `LearnerPlanHttpResponse`.
public struct LearnerPlan: Sendable, Equatable {
    public let correlationId: String
    public let recommendedSession: RecommendedSession
    public let focusAreas: [String]

    public init(
        correlationId: String,
        recommendedSession: RecommendedSession,
        focusAreas: [String]
    ) {
        self.correlationId = correlationId
        self.recommendedSession = recommendedSession
        self.focusAreas = focusAreas
    }
}

public struct RecommendedSession: Sendable, Equatable {
    /// One of the snake_case values the backend router understands
    /// (open_practice, guided_lesson, pronunciation_drill, …). Mapping to
    /// a `RealtimeTutorIntent` uses the same fallback rules the debrief
    /// recommendation does.
    public let activityIntent: String
    public let focusTitle: String
    public let reason: String

    public init(activityIntent: String, focusTitle: String, reason: String) {
        self.activityIntent = activityIntent
        self.focusTitle = focusTitle
        self.reason = reason
    }

    /// Reuses the debrief mapping so unknown intents fall back to
    /// `.openPractice` and empty focus titles get safe placeholders.
    public var intent: RealtimeTutorIntent {
        DebriefRecommendedDrill(
            activityIntent: activityIntent,
            focusTitle: focusTitle,
            reason: reason
        ).intent
    }
}

/// Lifecycle of the planner call — independent of the connection state so
/// the Home Today card can render loading / ready / failed independently
/// of the Talk session.
public enum LearnerPlanState: Sendable, Equatable {
    case idle
    case loading
    case ready(LearnerPlan)
    case failed(String)
}

public protocol LearnerPlanService: Sendable {
    func fetchTodayPlan(accessToken: String) async throws -> LearnerPlan
}

public enum LearnerPlanServiceError: Error, Equatable {
    case notConfigured(reason: String)
    case authenticationRequired
    case transport
    case server(code: Int, message: String)
}

public struct NotConfiguredLearnerPlanService: LearnerPlanService {
    private let reason: String

    public init(reason: String = "Personalised learner plans aren't configured for this build yet.") {
        self.reason = reason
    }

    public func fetchTodayPlan(accessToken: String) async throws -> LearnerPlan {
        throw LearnerPlanServiceError.notConfigured(reason: reason)
    }
}
