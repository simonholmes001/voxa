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
    private let accessTokenProvider: @MainActor @Sendable () -> String?

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        correlationIDProvider: @escaping @Sendable () -> String = { UUID().uuidString },
        accessTokenProvider: @escaping @MainActor @Sendable () -> String?
    ) {
        self.baseURL = baseURL
        self.session = session
        self.correlationIDProvider = correlationIDProvider
        self.accessTokenProvider = accessTokenProvider
    }

    public func submit(_ profile: OnboardingProfile) async throws {
        guard let accessToken = await accessTokenProvider() else {
            throw OnboardingServiceError.authenticationRequired
        }

        let body = OnboardingSubmitRequestDTO(
            targetLanguage: profile.targetLanguage,
            nativeLanguage: profile.nativeLanguage,
            proficiencyLevel: profile.placementLevel.displayName,
            goals: profile.goals,
            dailyMinutes: profile.minutesPerDay
        )

        let _: OnboardingSubmitResponseDTO = try await post("api/onboarding", body: body, accessToken: accessToken)
    }

    public func resume() async throws -> OnboardingProfile? {
        guard let accessToken = await accessTokenProvider() else {
            throw OnboardingServiceError.authenticationRequired
        }

        do {
            let response: ResumeCheckpointResponseDTO = try await get("api/session/resume", accessToken: accessToken)

            guard let cefrLevel = CEFRLevel(rawValue: response.profile.proficiencyLevel.lowercased()) else {
                throw OnboardingServiceError.invalidResponse
            }

            return OnboardingProfile(
                targetLanguage: response.profile.targetLanguage,
                nativeLanguage: response.profile.nativeLanguage,
                goals: response.profile.goals,
                minutesPerDay: response.profile.dailyMinutes,
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
        } catch let error as URLError {
            throw Self.mapTransportError(error)
        } catch {
            throw OnboardingServiceError.transportUnavailable
        }

        guard let http = response as? HTTPURLResponse else {
            throw OnboardingServiceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.mapError(status: http.statusCode, data: data)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw OnboardingServiceError.invalidResponse
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
        } catch let error as URLError {
            throw Self.mapTransportError(error)
        } catch {
            throw OnboardingServiceError.transportUnavailable
        }

        guard let http = response as? HTTPURLResponse else {
            throw OnboardingServiceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.mapError(status: http.statusCode, data: data)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw OnboardingServiceError.invalidResponse
        }
    }

    private static func mapError(status: Int, data: Data) -> OnboardingServiceError {
        switch status {
        case 404:
            return .notFound
        case 401, 403:
            return .authenticationRequired
        case 400, 422:
            return .unavailable
        default:
            return status >= 500 ? .serverUnavailable : .unavailable
        }
    }

    private static func mapTransportError(_ error: URLError) -> OnboardingServiceError {
        switch error.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .timedOut:
            return .transportUnavailable
        default:
            return .unavailable
        }
    }
}
