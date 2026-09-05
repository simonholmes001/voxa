import Foundation
import VoxaOnboarding
import VoxaProfiles

/// Saves per-language settings via `POST /api/onboarding`, which is idempotent
/// per (learner, targetLanguage). The expected `version` is sent as `If-Match`;
/// a stale version returns 409 -> `versionConflict`.
public struct VoxaBackendLanguageSettingsService: LanguageSettingsService {
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

    public func update(languageKey: String, profile: OnboardingProfile, expectedVersion: Int) async throws -> Int {
        guard let token = await accessTokenProvider() else {
            throw LanguageProfilesError.authenticationRequired
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/onboarding"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(correlationIDProvider(), forHTTPHeaderField: "X-Correlation-Id")
        request.setValue("\(expectedVersion)", forHTTPHeaderField: "If-Match")
        request.httpBody = try JSONEncoder().encode(
            OnboardingSubmitRequestDTO(
                targetLanguage: languageKey,
                nativeLanguage: profile.nativeLanguage,
                proficiencyLevel: profile.placementLevel.displayName,
                goals: profile.goals,
                dailyMinutes: profile.minutesPerDay
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LanguageProfilesError.transport
        }
        guard let http = response as? HTTPURLResponse else {
            throw LanguageProfilesError.transport
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.mapError(status: http.statusCode, data: data)
        }
        do {
            return try JSONDecoder().decode(OnboardingSubmitResponseDTO.self, from: data).version
        } catch {
            throw LanguageProfilesError.transport
        }
    }

    private static func mapError(status: Int, data: Data) -> LanguageProfilesError {
        let payload = try? JSONDecoder().decode(ApiErrorDTO.self, from: data)
        switch (status, payload?.code) {
        case (401, _):
            return .authenticationRequired
        case (409, _):
            return .versionConflict
        default:
            return .server(code: status, message: payload?.message ?? "The server returned an error.")
        }
    }
}
