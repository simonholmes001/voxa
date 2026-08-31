import Foundation
import VoxaOnboarding

/// Backend-backed implementation of `OnboardingService` for the Voxa
/// onboarding endpoint (`POST /api/onboarding`).
///
/// The contract is isolated behind the DTOs in `OnboardingContractDTOs.swift`;
/// this type maps them to and from `VoxaOnboarding` domain types. It has no
/// default base URL — the app composition layer must supply one, and callers get
/// a clear error if it is missing (see `UnavailableOnboardingService`).
///
/// Requests are authenticated with the app-session access token from `VoxaAuth`.
public struct VoxaBackendOnboardingService: OnboardingService {
    private let baseURL: URL
    private let session: URLSession
    private let correlationIDProvider: @Sendable () -> String
    private let accessTokenProvider: @Sendable () -> String?

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        correlationIDProvider: @escaping @Sendable () -> String = { UUID().uuidString },
        accessTokenProvider: @escaping @Sendable () -> String?
    ) {
        self.baseURL = baseURL
        self.session = session
        self.correlationIDProvider = correlationIDProvider
        self.accessTokenProvider = accessTokenProvider
    }

    public func submit(_ profile: OnboardingProfile) async throws {
        guard let accessToken = accessTokenProvider() else {
            throw OnboardingServiceError.unavailable
        }

        let body = OnboardingSubmitRequestDTO(
            targetLanguage: profile.targetLanguage,
            nativeLanguage: profile.nativeLanguage,
            proficiencyLevel: profile.placementLevel.rawValue,
            goals: [profile.goal.rawValue],
            dailyMinutes: profile.minutesPerDay
        )

        let _: OnboardingSubmitResponseDTO = try await post("api/onboarding", body: body, accessToken: accessToken)
    }

    public func resume() async throws -> OnboardingProfile? {
        guard let accessToken = accessTokenProvider() else {
            throw OnboardingServiceError.unavailable
        }

        do {
            let response: ResumeCheckpointResponseDTO = try await get("api/session/resume", accessToken: accessToken)

            // Map the DTO to OnboardingProfile
            // We need to infer the goal and minutesPerDay since they're not in the resume response
            // For MVP, use defaults when resuming
            guard let cefrLevel = CEFRLevel(rawValue: response.profile.proficiencyLevel) else {
                throw OnboardingServiceError.unavailable
            }

            return OnboardingProfile(
                targetLanguage: response.profile.targetLanguage,
                nativeLanguage: response.profile.nativeLanguage,
                goal: .general, // Default goal when resuming
                minutesPerDay: 15, // Default minutes when resuming
                placementLevel: cefrLevel
            )
        } catch OnboardingServiceError.notFound {
            return nil
        }
    }

    private func post<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body,
        accessToken: String
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(correlationIDProvider(), forHTTPHeaderField: "X-Correlation-Id")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OnboardingServiceError.unavailable
        }

        guard let http = response as? HTTPURLResponse else {
            throw OnboardingServiceError.unavailable
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.mapError(status: http.statusCode, data: data)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw OnboardingServiceError.unavailable
        }
    }

    private func get<Response: Decodable>(
        _ path: String,
        accessToken: String
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(correlationIDProvider(), forHTTPHeaderField: "X-Correlation-Id")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OnboardingServiceError.unavailable
        }

        guard let http = response as? HTTPURLResponse else {
            throw OnboardingServiceError.unavailable
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.mapError(status: http.statusCode, data: data)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw OnboardingServiceError.unavailable
        }
    }

    private static func mapError(status: Int, data: Data) -> OnboardingServiceError {
        switch status {
        case 404:
            return .notFound
        case 401, 403:
            return .unavailable
        case 400, 422:
            return .unavailable
        default:
            return .unavailable
        }
    }
}
