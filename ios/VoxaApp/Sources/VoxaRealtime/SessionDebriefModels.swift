import Foundation

/// One turn of the Talk session transcript, captured by the transport as
/// OpenAI Realtime emits transcript events. `role` is "learner" or "tutor".
public struct TranscriptTurn: Sendable, Equatable, Codable {
    public let role: String
    public let text: String

    public init(role: String, text: String) {
        self.role = role
        self.text = text
    }

    public static let learnerRole = "learner"
    public static let tutorRole = "tutor"
}

/// Result of the backend debrief pass. Every list is non-nil but may be empty
/// (the assessor is instructed to leave lists empty for very short sessions
/// rather than invent content to fill them).
public struct SessionDebrief: Sendable, Equatable {
    public let correlationId: String
    public let summary: String
    public let recurringMistakes: [DebriefRecurringMistake]
    public let usefulPhrases: [String]
    public let pronunciationNotes: [String]
    public let recommendedNextDrill: DebriefRecommendedDrill

    public init(
        correlationId: String,
        summary: String,
        recurringMistakes: [DebriefRecurringMistake],
        usefulPhrases: [String],
        pronunciationNotes: [String],
        recommendedNextDrill: DebriefRecommendedDrill
    ) {
        self.correlationId = correlationId
        self.summary = summary
        self.recurringMistakes = recurringMistakes
        self.usefulPhrases = usefulPhrases
        self.pronunciationNotes = pronunciationNotes
        self.recommendedNextDrill = recommendedNextDrill
    }
}

public struct DebriefRecurringMistake: Sendable, Equatable {
    public enum Severity: String, Sendable, Equatable {
        case low, medium, high
    }
    public let pattern: String
    public let example: String
    public let severity: Severity

    public init(pattern: String, example: String, severity: Severity) {
        self.pattern = pattern
        self.example = example
        self.severity = severity
    }
}

public struct DebriefRecommendedDrill: Sendable, Equatable {
    /// One of the snake_case values `RealtimeCoachingSettings.applying(_:)`
    /// emits (open_practice, guided_lesson, pronunciation_drill, …). Unknown
    /// values are treated by the UI as `.openPractice` for safety.
    public let activityIntent: String
    public let focusTitle: String
    public let reason: String

    public init(activityIntent: String, focusTitle: String, reason: String) {
        self.activityIntent = activityIntent
        self.focusTitle = focusTitle
        self.reason = reason
    }

    /// Maps the backend's snake_case intent string back to a
    /// `RealtimeTutorIntent` so the debrief screen can launch the next
    /// session directly.
    public var intent: RealtimeTutorIntent {
        switch activityIntent {
        case "open_practice", "practice":
            return .openPractice
        case "guided_lesson", "lesson":
            return .lesson(title: focusTitle.isEmpty ? nil : focusTitle)
        case "review":
            return .review(dueCount: 0, focusTitle: focusTitle.isEmpty ? nil : focusTitle)
        case "pronunciation_drill":
            return .pronunciationDrill(focusTitle: focusTitle.isEmpty ? nil : focusTitle)
        case "roleplay":
            return .roleplay(scenarioTitle: focusTitle.isEmpty ? "An everyday café order" : focusTitle)
        case "mistakes_replay":
            return .mistakesReplay(focusTitle: focusTitle.isEmpty ? nil : focusTitle)
        case "vocabulary_drill":
            return .vocabularyDrill(focusTitle: focusTitle.isEmpty ? nil : focusTitle)
        case "listening_practice":
            return .listeningPractice(focusTitle: focusTitle.isEmpty ? nil : focusTitle)
        case "key_language":
            return .keyLanguage(topic: focusTitle.isEmpty ? "the language coming up next" : focusTitle)
        default:
            return .openPractice
        }
    }
}

/// Lifecycle of the post-session debrief. Independent of the connection state
/// (RealtimeConnectionState) so the debrief can be requested after the Talk
/// session has already `.ended`. Consumers show a card, a spinner, or an
/// error banner based on this.
public enum DebriefState: Sendable, Equatable {
    case idle
    case loading
    case ready(SessionDebrief)
    case failed(String)
}

/// Backend service that turns a captured transcript into a `SessionDebrief`.
public protocol DebriefService: Sendable {
    func generateDebrief(
        settings: RealtimeCoachingSettings,
        transcript: [TranscriptTurn],
        accessToken: String
    ) async throws -> SessionDebrief
}

public enum DebriefServiceError: Error, Equatable {
    case notConfigured(reason: String)
    case authenticationRequired
    case transport
    case server(code: Int, message: String)
}

public struct NotConfiguredDebriefService: DebriefService {
    private let reason: String

    public init(reason: String = "Voice-session debriefs aren't configured for this build yet.") {
        self.reason = reason
    }

    public func generateDebrief(
        settings: RealtimeCoachingSettings,
        transcript: [TranscriptTurn],
        accessToken: String
    ) async throws -> SessionDebrief {
        throw DebriefServiceError.notConfigured(reason: reason)
    }
}
