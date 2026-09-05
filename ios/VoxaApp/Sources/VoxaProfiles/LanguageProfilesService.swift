/// Client-side seam for the language-profiles endpoints. The concrete HTTP
/// client lives in `VoxaNetworking`; wire DTOs are isolated there.
public protocol LanguageProfilesService: Sendable {
    /// `GET /api/language-profiles`.
    func list() async throws -> LanguageProfileList
    /// `POST /api/language-profiles/{languageKey}/select`; returns the new
    /// active language key.
    func selectActive(languageKey: String) async throws -> String
}

public enum LanguageProfilesError: Error, Equatable {
    case notConfigured(String)
    case authenticationRequired
    case unknownLanguage
    case versionConflict
    case server(code: Int, message: String)
    case transport
}

/// Fallback used when the backend base URL is missing, so a misconfigured
/// build fails clearly instead of silently.
public struct NotConfiguredLanguageProfilesService: LanguageProfilesService {
    private let reason: String

    public init(reason: String = "The backend base URL (VOXA_API_BASE_URL) is not configured.") {
        self.reason = reason
    }

    public func list() async throws -> LanguageProfileList {
        throw LanguageProfilesError.notConfigured(reason)
    }

    public func selectActive(languageKey: String) async throws -> String {
        throw LanguageProfilesError.notConfigured(reason)
    }
}
