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
    /// A short one-shot sample of the selected voice/tone/speed.
    case voicePreview

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
        case .voicePreview: return "Voice preview"
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
        case .voicePreview:
            return "Preview your tutor voice?"
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
        case .voicePreview: return "Preview voice"
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
    /// The learner's native language, sent to the backend so the tutor
    /// prompt can scaffold beginner lessons in L1. Optional for backward
    /// compatibility with older clients (server falls back to "English").
    public var nativeLanguage: String?
    public var aiTutorPreferences: AiTutorPreferences

    public init(
        coachingMode: String = "tutor",
        proficiencyBand: String,
        targetLanguage: String,
        sessionIntent: String? = nil,
        focusTitle: String? = nil,
        dueReviewCount: Int? = nil,
        nativeLanguage: String? = nil,
        aiTutorPreferences: AiTutorPreferences = .default
    ) {
        self.coachingMode = coachingMode
        self.proficiencyBand = proficiencyBand
        self.targetLanguage = targetLanguage
        self.sessionIntent = sessionIntent
        self.focusTitle = focusTitle
        self.dueReviewCount = dueReviewCount
        self.nativeLanguage = nativeLanguage
        self.aiTutorPreferences = aiTutorPreferences
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
        case .voicePreview:
            copy.sessionIntent = "voice_preview"
            copy.focusTitle = nil
            copy.dueReviewCount = nil
        }
        return copy
    }
}

/// Learner-facing AI tutor customization for live Realtime sessions.
/// These values map to OpenAI Realtime session audio output configuration
/// plus instruction guidance. OpenAI exposes named voices rather than
/// male/female categories, so Voxa keeps the model honest and stores voices by
/// supported voice id.
public struct AiTutorPreferences: Sendable, Equatable, Codable {
    public var voice: AiTutorVoice
    public var tone: AiTutorTone
    public var speed: Double
    public var customInstructions: String

    public static let minimumSpeed = 0.25
    public static let maximumSpeed = 1.5
    public static let previewText = "Hi, I'm your Voxa tutor. We'll keep this focused, natural, and easy to practise."
    public static let `default` = AiTutorPreferences(
        voice: .marin,
        tone: .supportive,
        speed: 1,
        customInstructions: ""
    )

    public init(
        voice: AiTutorVoice = .marin,
        tone: AiTutorTone = .supportive,
        speed: Double = 1,
        customInstructions: String = ""
    ) {
        self.voice = voice
        self.tone = tone
        self.speed = min(max(speed, Self.minimumSpeed), Self.maximumSpeed)
        self.customInstructions = String(customInstructions.prefix(400))
    }

    public var instructionText: String {
        let custom = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if custom.isEmpty { return tone.instruction }
        return "\(tone.instruction) \(custom)"
    }
}

public enum AiTutorVoice: String, CaseIterable, Sendable, Codable, Identifiable {
    case alloy
    case ash
    case ballad
    case coral
    case echo
    case sage
    case shimmer
    case verse
    case marin
    case cedar

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .alloy: return "Alloy"
        case .ash: return "Ash"
        case .ballad: return "Ballad"
        case .coral: return "Coral"
        case .echo: return "Echo"
        case .sage: return "Sage"
        case .shimmer: return "Shimmer"
        case .verse: return "Verse"
        case .marin: return "Marin"
        case .cedar: return "Cedar"
        }
    }
}

public enum AiTutorTone: String, CaseIterable, Sendable, Codable, Identifiable {
    case supportive
    case calm
    case energetic
    case direct
    case playful

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .supportive: return "Supportive"
        case .calm: return "Calm"
        case .energetic: return "Energetic"
        case .direct: return "Direct"
        case .playful: return "Playful"
        }
    }

    public var instruction: String {
        switch self {
        case .supportive:
            return "Sound warm, patient, and encouraging while keeping the learner moving."
        case .calm:
            return "Sound calm, measured, and reassuring; give the learner room to think."
        case .energetic:
            return "Sound upbeat and lively without rushing or overwhelming the learner."
        case .direct:
            return "Sound concise, clear, and practical; correct efficiently and avoid extra chatter."
        case .playful:
            return "Sound lightly playful and curious while staying focused on language practice."
        }
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
