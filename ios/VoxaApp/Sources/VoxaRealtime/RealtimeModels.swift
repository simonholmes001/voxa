import Foundation

/// The learner's reason for opening the voice tutor. The app uses this to set
/// the Talk screen state and to shape backend Realtime tutor instructions —
/// each case maps to a distinct server-side prompt template
/// (`realtime-tutor/<activity>.v1`).
public enum RealtimeTutorIntent: Sendable, Equatable {
    /// Free conversation. Default when no more specific surface launched Talk.
    case openPractice
    /// Guided lesson on a named topic.
    case lesson(title: String?)
    /// Spaced-repetition-style review.
    case review(dueCount: Int, focusTitle: String? = nil)
    /// Targeted pronunciation practice (minimal pairs, articulatory feedback).
    case pronunciationDrill(focusTitle: String? = nil)
    /// Scenario-based roleplay ("Order coffee in Paris", …). Focus title
    /// carries the scenario.
    case roleplay(scenarioTitle: String)
    /// Fix recurring errors from previous sessions.
    case mistakesReplay(focusTitle: String? = nil)
    /// New vocabulary work on a small themed set.
    case vocabularyDrill(focusTitle: String? = nil)
    /// Listening-first: tutor produces longer chunks, learner responds.
    case listeningPractice(focusTitle: String? = nil)
    /// "Before you start" briefing on key structures the learner is about to
    /// encounter.
    case keyLanguage(topic: String)

    public var title: String {
        switch self {
        case .openPractice: return "Speaking practice"
        case .lesson: return "Voice lesson"
        case let .review(_, focusTitle): return focusTitle ?? "Review session"
        case .pronunciationDrill: return "Pronunciation drill"
        case let .roleplay(scenario): return scenario
        case .mistakesReplay: return "Fix recent mistakes"
        case .vocabularyDrill: return "Vocabulary drill"
        case .listeningPractice: return "Listening practice"
        case let .keyLanguage(topic): return topic
        }
    }

    public var prompt: String {
        switch self {
        case .openPractice:
            return "Ready to practise speaking?"
        case let .lesson(title):
            guard let title, !title.isEmpty else { return "Ready for your voice lesson?" }
            return "Ready for \(title)?"
        case let .review(dueCount, focusTitle):
            if let focusTitle, !focusTitle.isEmpty {
                return "Ready to practise \(focusTitle.lowercased())?"
            }
            guard dueCount > 0 else { return "Ready to review with your tutor?" }
            return "Ready to review \(dueCount) due items?"
        case .pronunciationDrill:
            return "Ready to work on your pronunciation?"
        case let .roleplay(scenario):
            return "Ready to roleplay — \(scenario)?"
        case .mistakesReplay:
            return "Ready to fix your recent mistakes?"
        case .vocabularyDrill:
            return "Ready for some new words?"
        case .listeningPractice:
            return "Ready to work on your listening?"
        case let .keyLanguage(topic):
            return "Ready for a quick brief on \(topic)?"
        }
    }

    public var startButtonTitle: String {
        switch self {
        case .openPractice: return "Start talking"
        case .lesson: return "Start voice lesson"
        case .review: return "Start review"
        case .pronunciationDrill: return "Start drill"
        case .roleplay: return "Start scene"
        case .mistakesReplay: return "Start fixing"
        case .vocabularyDrill: return "Start drill"
        case .listeningPractice: return "Start listening"
        case .keyLanguage: return "Start briefing"
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

    /// Emits the backend-facing `SessionIntent` string for the activity. The
    /// backend's prompt router
    /// (`OpenAiRealtimeClientSecretIssuer.ResolvePromptRef`) matches on these
    /// exact snake_case values. Legacy short forms ("practice", "lesson")
    /// still route correctly for backward compatibility with older clients.
    public func applying(_ intent: RealtimeTutorIntent) -> RealtimeCoachingSettings {
        var copy = self
        switch intent {
        case .openPractice:
            copy.sessionIntent = "open_practice"
            copy.focusTitle = nil
            copy.dueReviewCount = nil
        case let .lesson(title):
            copy.sessionIntent = "guided_lesson"
            copy.focusTitle = title
            copy.dueReviewCount = nil
        case let .review(dueCount, focusTitle):
            copy.sessionIntent = "review"
            copy.focusTitle = focusTitle
            copy.dueReviewCount = dueCount
        case let .pronunciationDrill(focusTitle):
            copy.sessionIntent = "pronunciation_drill"
            copy.focusTitle = focusTitle
            copy.dueReviewCount = nil
        case let .roleplay(scenarioTitle):
            copy.sessionIntent = "roleplay"
            copy.focusTitle = scenarioTitle
            copy.dueReviewCount = nil
        case let .mistakesReplay(focusTitle):
            copy.sessionIntent = "mistakes_replay"
            copy.focusTitle = focusTitle
            copy.dueReviewCount = nil
        case let .vocabularyDrill(focusTitle):
            copy.sessionIntent = "vocabulary_drill"
            copy.focusTitle = focusTitle
            copy.dueReviewCount = nil
        case let .listeningPractice(focusTitle):
            copy.sessionIntent = "listening_practice"
            copy.focusTitle = focusTitle
            copy.dueReviewCount = nil
        case let .keyLanguage(topic):
            copy.sessionIntent = "key_language"
            copy.focusTitle = topic
            copy.dueReviewCount = nil
        }
        return copy
    }
}

/// The short-lived credential the backend issues for a Realtime session. The
/// permanent OpenAI key stays server-side; `clientSecret` is an ephemeral token
/// the device uses to connect directly to OpenAI Realtime.
public struct RealtimeSessionCredential: Sendable, Equatable {
    public var correlationId: String
    public var clientSecret: String
    public var model: String
    public var reasoningEffort: String
    public var expiresAt: Date
    public var settings: RealtimeCoachingSettings

    public init(
        correlationId: String,
        clientSecret: String,
        model: String,
        reasoningEffort: String,
        expiresAt: Date,
        settings: RealtimeCoachingSettings
    ) {
        self.correlationId = correlationId
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
