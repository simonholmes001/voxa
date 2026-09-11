import Foundation
import VoxaRealtime

/// Backend-backed `LearnerCourseService` for `GET /api/learner/course` and
/// `POST /api/learner/course/reassess`. Sends the caller's access token as
/// a bearer token.
public struct VoxaBackendLearnerCourseService: LearnerCourseService {
    private let baseURL: URL
    private let session: URLSession
    private let correlationIDProvider: @Sendable () -> String
    private let requestTimeout: TimeInterval
    /// Reassessment can take a while — the CurriculumModel is high
    /// reasoning. iOS shows a "Reassessing…" state throughout, so the
    /// service allows a longer wall-clock than the read path.
    private let reassessTimeout: TimeInterval

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        correlationIDProvider: @escaping @Sendable () -> String = { UUID().uuidString },
        requestTimeout: TimeInterval = 30,
        reassessTimeout: TimeInterval = 90
    ) {
        self.baseURL = baseURL
        self.session = session
        self.correlationIDProvider = correlationIDProvider
        self.requestTimeout = requestTimeout
        self.reassessTimeout = reassessTimeout
    }

    public func fetchCourse(accessToken: String) async throws -> LearnerCourse {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/learner/course"))
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(correlationIDProvider(), forHTTPHeaderField: "X-Correlation-Id")

        return try await performCourseCall(request)
    }

    public func reassessCourse(
        request reassessmentRequest: String?,
        accessToken: String
    ) async throws -> LearnerCourse {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/learner/course/reassess"))
        request.httpMethod = "POST"
        request.timeoutInterval = reassessTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(correlationIDProvider(), forHTTPHeaderField: "X-Correlation-Id")
        request.httpBody = try JSONEncoder().encode(
            CourseReassessmentRequestDTO(reassessmentRequest: reassessmentRequest))

        return try await performCourseCall(request)
    }

    private func performCourseCall(_ request: URLRequest) async throws -> LearnerCourse {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LearnerCourseServiceError.transport
        }
        guard let http = response as? HTTPURLResponse else {
            throw LearnerCourseServiceError.transport
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.mapError(status: http.statusCode, data: data)
        }
        do {
            return try JSONDecoder().decode(LearnerCourseResponseDTO.self, from: data).toCourse()
        } catch {
            throw LearnerCourseServiceError.transport
        }
    }

    private static func mapError(status: Int, data: Data) -> LearnerCourseServiceError {
        let payload = try? JSONDecoder().decode(ApiErrorDTO.self, from: data)
        switch status {
        case 401: return .authenticationRequired
        case 404: return .notFound
        default: return .server(code: status, message: payload?.message ?? "The server returned an error.")
        }
    }
}

// MARK: - DTOs

struct CourseReassessmentRequestDTO: Encodable {
    let reassessmentRequest: String?
}

struct LearnerCourseResponseDTO: Decodable {
    let correlationId: String
    let planId: String
    let title: String
    let lessons: [PlannedLessonDTO]

    func toCourse() -> LearnerCourse {
        LearnerCourse(
            correlationId: correlationId,
            planId: planId,
            title: title,
            lessons: lessons.map { $0.toDomain() })
    }
}

struct PlannedLessonDTO: Decodable {
    let lessonId: String
    let title: String
    let learningObjective: String
    let order: Int
    let estimatedMinutes: Int
    let status: String

    func toDomain() -> PlannedLesson {
        PlannedLesson(
            lessonId: lessonId,
            title: title,
            learningObjective: learningObjective,
            order: order,
            estimatedMinutes: estimatedMinutes,
            status: PlannedLessonStatus(rawFromServer: status))
    }
}
