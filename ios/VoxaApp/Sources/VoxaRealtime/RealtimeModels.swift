import Foundation

/// The learner's reason for opening the voice tutor. This is currently client
/// UI state; the backend Realtime contract still receives the supported
/// `tutor` coaching mode until server-side prompt modes are expanded.
public enum RealtimeTutorIntent: Sendable, Equatable {
    case openPractice
    case lesson(title: String?)
    case review(dueCount: Int)

    public var title: String {
        switch self {
        case .openPractice:
            return "Speaking practice"
        case .lesson:
            return "Voice lesson"
        case .review:
            return "Review session"
        }
    }

    public var prompt: String {
        switch self {
        case .openPractice:
            return "Ready to practise speaking?"
        case let .lesson(title):
            guard let title, !title.isEmpty else {
                return "Ready for your voice lesson?"
            }
            return "Ready for \(title)?"
        case let .review(dueCount):
            guard dueCount > 0 else {
                return "Ready to review with your tutor?"
            }
            return "Ready to review \(dueCount) due items?"
        }
    }
}

/// Settings that shape a Realtime tutoring session. Sent to the backend when
/// requesting a session credential (see `POST /api/realtime/session`).
public struct RealtimeCoachingSettings: Sendable, Equatable {
    public var coachingMode: String
    public var proficiencyBand: String
    public var targetLanguage: String
    public var sessionIntent: String?
    public var focusTitle: String?
    public var dueReviewCount: Int?

    public init(
        coachingMode: String = "tutor",
        proficiencyBand: String,
        targetLanguage: String,
        sessionIntent: String? = nil,
        focusTitle: String? = nil,
        dueReviewCount: Int? = nil
    ) {
        self.coachingMode = coachingMode
        self.proficiencyBand = proficiencyBand
        self.targetLanguage = targetLanguage
        self.sessionIntent = sessionIntent
        self.focusTitle = focusTitle
        self.dueReviewCount = dueReviewCount
    }

    public func applying(_ intent: RealtimeTutorIntent) -> RealtimeCoachingSettings {
        var copy = self
        switch intent {
        case .openPractice:
            copy.sessionIntent = "practice"
            copy.focusTitle = nil
            copy.dueReviewCount = nil
        case let .lesson(title):
            copy.sessionIntent = "lesson"
            copy.focusTitle = title
            copy.dueReviewCount = nil
        case let .review(dueCount):
            copy.sessionIntent = "review"
            copy.focusTitle = nil
            copy.dueReviewCount = dueCount
        }
        return copy
    }
}

/// The short-lived credential the backend issues for a Realtime session. The
/// permanent OpenAI key stays server-side; `clientSecret` is an ephemeral token
/// the device uses to connect directly to OpenAI Realtime.
public struct RealtimeSessionCredential: Sendable, Equatable {
    public var clientSecret: String
    public var model: String
    public var reasoningEffort: String
    public var expiresAt: Date
    public var settings: RealtimeCoachingSettings

    public init(
        clientSecret: String,
        model: String,
        reasoningEffort: String,
        expiresAt: Date,
        settings: RealtimeCoachingSettings
    ) {
        self.clientSecret = clientSecret
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.expiresAt = expiresAt
        self.settings = settings
    }

    public func isExpired(asOf now: Date = Date(), leeway: TimeInterval = 5) -> Bool {
        now.addingTimeInterval(leeway) >= expiresAt
    }
}
