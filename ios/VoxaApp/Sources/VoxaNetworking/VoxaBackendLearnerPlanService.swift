import Foundation
import VoxaRealtime

/// Backend-backed `LearnerPlanService` for `GET /api/learner/plan`. Sends
/// the caller's access token as a bearer token. Called by Home + Practice
/// on tab appearance to render the Today card.
public struct VoxaBackendLearnerPlanService: LearnerPlanService {
    private let baseURL: URL
    private let session: URLSession
    private let correlationIDProvider: @Sendable () -> String
    private let requestTimeout: TimeInterval

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        correlationIDProvider: @escaping @Sendable () -> String = { UUID().uuidString },
        requestTimeout: TimeInterval = 30
    ) {
        self.baseURL = baseURL
        self.session = session
        self.correlationIDProvider = correlationIDProvider
        self.requestTimeout = requestTimeout
    }

    public func fetchTodayPlan(accessToken: String) async throws -> LearnerPlan {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/learner/plan"))
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(correlationIDProvider(), forHTTPHeaderField: "X-Correlation-Id")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LearnerPlanServiceError.transport
        }
        guard let http = response as? HTTPURLResponse else {
            throw LearnerPlanServiceError.transport
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.mapError(status: http.statusCode, data: data)
        }
        do {
            return try JSONDecoder().decode(LearnerPlanResponseDTO.self, from: data).toPlan()
        } catch {
            throw LearnerPlanServiceError.transport
        }
    }

    private static func mapError(status: Int, data: Data) -> LearnerPlanServiceError {
        let payload = try? JSONDecoder().decode(ApiErrorDTO.self, from: data)
        switch status {
        case 401: return .authenticationRequired
        default: return .server(code: status, message: payload?.message ?? "The server returned an error.")
        }
    }
}

// MARK: - DTOs

struct LearnerPlanResponseDTO: Decodable {
    let correlationId: String
    let recommendedSession: RecommendedSessionDTO
    let focusAreas: [String]

    func toPlan() -> LearnerPlan {
        LearnerPlan(
            correlationId: correlationId,
            recommendedSession: recommendedSession.toDomain(),
            focusAreas: focusAreas)
    }
}

struct RecommendedSessionDTO: Decodable {
    let activityIntent: String
    let focusTitle: String
    let reason: String

    func toDomain() -> RecommendedSession {
        RecommendedSession(activityIntent: activityIntent, focusTitle: focusTitle, reason: reason)
    }
}
