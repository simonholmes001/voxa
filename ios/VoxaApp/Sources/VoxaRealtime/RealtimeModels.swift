import Foundation

/// Settings that shape a Realtime tutoring session. Sent to the backend when
/// requesting a session credential (see `POST /api/realtime/session`).
public struct RealtimeCoachingSettings: Sendable, Equatable {
    public var coachingMode: String
    public var proficiencyBand: String
    public var targetLanguage: String

    public init(coachingMode: String = "tutor", proficiencyBand: String, targetLanguage: String) {
        self.coachingMode = coachingMode
        self.proficiencyBand = proficiencyBand
        self.targetLanguage = targetLanguage
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
