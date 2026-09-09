import Foundation
import VoxaRealtime

/// Backend-backed `DebriefService` for `POST /api/realtime/debrief`. Sends
/// the captured Talk session transcript to the backend, which calls the
/// AssessmentModel with the `realtime-tutor/debrief.v1` prompt and returns a
/// structured summary. Requires an authenticated app session; the access
/// token is sent as a bearer token.
public struct VoxaBackendDebriefService: DebriefService {
    private let baseURL: URL
    private let session: URLSession
    private let correlationIDProvider: @Sendable () -> String
    private let requestTimeout: TimeInterval

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        correlationIDProvider: @escaping @Sendable () -> String = { UUID().uuidString },
        requestTimeout: TimeInterval = 60
    ) {
        self.baseURL = baseURL
        self.session = session
        self.correlationIDProvider = correlationIDProvider
        self.requestTimeout = requestTimeout
    }

    public func generateDebrief(
        settings: RealtimeCoachingSettings,
        transcript: [TranscriptTurn],
        accessToken: String
    ) async throws -> SessionDebrief {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/realtime/debrief"))
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(correlationIDProvider(), forHTTPHeaderField: "X-Correlation-Id")
        request.httpBody = try JSONEncoder().encode(
            SessionDebriefRequestDTO(
                coachingMode: settings.coachingMode,
                proficiencyBand: settings.proficiencyBand,
                targetLanguage: settings.targetLanguage,
                sessionIntent: settings.sessionIntent,
                focusTitle: settings.focusTitle,
                dueReviewCount: settings.dueReviewCount,
                transcript: transcript.map { turn in
                    TranscriptTurnDTO(role: turn.role, text: turn.text)
                }))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw DebriefServiceError.transport
        }
        guard let http = response as? HTTPURLResponse else {
            throw DebriefServiceError.transport
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.mapError(status: http.statusCode, data: data)
        }
        do {
            return try JSONDecoder().decode(SessionDebriefResponseDTO.self, from: data).toDebrief()
        } catch {
            throw DebriefServiceError.transport
        }
    }

    private static func mapError(status: Int, data: Data) -> DebriefServiceError {
        let payload = try? JSONDecoder().decode(ApiErrorDTO.self, from: data)
        switch status {
        case 401: return .authenticationRequired
        default: return .server(code: status, message: payload?.message ?? "The server returned an error.")
        }
    }
}

// MARK: - DTOs

struct SessionDebriefRequestDTO: Encodable {
    let coachingMode: String
    let proficiencyBand: String
    let targetLanguage: String
    let sessionIntent: String?
    let focusTitle: String?
    let dueReviewCount: Int?
    let transcript: [TranscriptTurnDTO]
}

struct TranscriptTurnDTO: Codable {
    let role: String
    let text: String
}

struct SessionDebriefResponseDTO: Decodable {
    let correlationId: String
    let summary: String
    let recurringMistakes: [RecurringMistakeDTO]
    let usefulPhrases: [String]
    let pronunciationNotes: [String]
    let recommendedNextDrill: RecommendedDrillDTO

    func toDebrief() -> SessionDebrief {
        SessionDebrief(
            correlationId: correlationId,
            summary: summary,
            recurringMistakes: recurringMistakes.map { $0.toDebrief() },
            usefulPhrases: usefulPhrases,
            pronunciationNotes: pronunciationNotes,
            recommendedNextDrill: recommendedNextDrill.toDebrief())
    }
}

struct RecurringMistakeDTO: Decodable {
    let pattern: String
    let example: String
    let severity: String

    func toDebrief() -> DebriefRecurringMistake {
        let normalized = severity.lowercased()
        let mapped: DebriefRecurringMistake.Severity =
            DebriefRecurringMistake.Severity(rawValue: normalized) ?? .low
        return DebriefRecurringMistake(pattern: pattern, example: example, severity: mapped)
    }
}

struct RecommendedDrillDTO: Decodable {
    let activityIntent: String
    let focusTitle: String
    let reason: String

    func toDebrief() -> DebriefRecommendedDrill {
        DebriefRecommendedDrill(
            activityIntent: activityIntent,
            focusTitle: focusTitle,
            reason: reason)
    }
}
