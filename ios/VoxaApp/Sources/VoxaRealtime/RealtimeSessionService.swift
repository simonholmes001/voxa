/// Client-side seam for requesting a Realtime session credential from the Voxa
/// backend (`POST /api/realtime/session`). The concrete HTTP client lives in
/// `VoxaNetworking`; the wire contract stays isolated there.
public protocol RealtimeSessionService: Sendable {
    func createSession(
        _ settings: RealtimeCoachingSettings,
        accessToken: String
    ) async throws -> RealtimeSessionCredential
}

public enum RealtimeSessionError: Error, Equatable {
    /// The backend base URL is not configured for this build.
    case notConfigured(String)
    /// The backend requires a valid app session (HTTP 401).
    case appSessionRequired
    /// The request was rejected as invalid (HTTP 400).
    case validation(String)
    /// The backend returned an unexpected error.
    case server(code: Int, message: String)
    /// The request could not reach the backend or the response was unreadable.
    case transport
}

/// Fallback service used when the backend base URL is missing, so a
/// misconfigured build fails clearly instead of silently.
public struct NotConfiguredRealtimeSessionService: RealtimeSessionService {
    private let reason: String

    public init(reason: String = "The backend base URL (VOXA_API_BASE_URL) is not configured.") {
        self.reason = reason
    }

    public func createSession(
        _ settings: RealtimeCoachingSettings,
        accessToken: String
    ) async throws -> RealtimeSessionCredential {
        throw RealtimeSessionError.notConfigured(reason)
    }
}
