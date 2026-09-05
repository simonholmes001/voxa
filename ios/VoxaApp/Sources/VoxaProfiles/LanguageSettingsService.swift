import VoxaOnboarding

/// Client-side seam for saving edits to a single language profile. The concrete
/// client updates it through the idempotent `POST /api/onboarding` endpoint,
/// using the profile `version` as the concurrency token (see
/// docs/api-contracts.md). Returns the new version on success.
public protocol LanguageSettingsService: Sendable {
    func update(
        languageKey: String,
        profile: OnboardingProfile,
        expectedVersion: Int
    ) async throws -> Int
}

/// Fallback used when the backend base URL is missing.
public struct NotConfiguredLanguageSettingsService: LanguageSettingsService {
    private let reason: String

    public init(reason: String = "The backend base URL (VOXA_API_BASE_URL) is not configured.") {
        self.reason = reason
    }

    public func update(languageKey: String, profile: OnboardingProfile, expectedVersion: Int) async throws -> Int {
        throw LanguageProfilesError.notConfigured(reason)
    }
}
