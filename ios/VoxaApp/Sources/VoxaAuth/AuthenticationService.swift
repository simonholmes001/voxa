/// Client-side seam for the backend Sign in with Apple exchange.
///
/// The concrete network client and the wire contract (endpoints, payloads,
/// token format) are backend responsibilities (#17 backend, #14). The iOS
/// layer depends only on this protocol, so the sign-in UI and session
/// lifecycle can be built and tested independently and wired to the real
/// client later via dependency injection.
public protocol AuthenticationService: Sendable {
    /// Exchanges an Apple identity proof for a backend-issued session.
    func exchange(_ proof: AppleIdentityProof) async throws -> AuthSession
    /// Refreshes an expired or soon-to-expire session.
    func refresh(_ session: AuthSession) async throws -> AuthSession
    /// Invalidates the backend session (logout / account session invalidation).
    func invalidate(_ session: AuthSession) async throws
}

public enum AuthenticationServiceError: Error, Equatable {
    /// No backend client is wired (e.g. previews/tests default service).
    case unavailable
    /// The backend base URL is not configured (see `VOXA_API_BASE_URL`).
    case notConfigured(String)
    /// Apple identity could not be verified by the backend (HTTP 401).
    case invalidAppleIdentity
    /// The refresh token is invalid, revoked, or expired (HTTP 401).
    case sessionExpired
    /// The request was rejected as invalid (HTTP 400).
    case validation(String)
    /// The backend returned an unexpected error.
    case server(code: Int, message: String)
    /// The request could not reach the backend or the response was unreadable.
    case transport
}

/// Default service used in previews/tests. Every call fails with
/// `.unavailable`.
public struct UnavailableAuthenticationService: AuthenticationService {
    public init() {}

    public func exchange(_ proof: AppleIdentityProof) async throws -> AuthSession {
        throw AuthenticationServiceError.unavailable
    }

    public func refresh(_ session: AuthSession) async throws -> AuthSession {
        throw AuthenticationServiceError.unavailable
    }

    public func invalidate(_ session: AuthSession) async throws {
        throw AuthenticationServiceError.unavailable
    }
}

/// Fallback service used by the app when the backend base URL is missing, so
/// the failure surfaces clearly at call time instead of silently doing nothing.
public struct NotConfiguredAuthenticationService: AuthenticationService {
    private let reason: String

    public init(reason: String = "The backend base URL (VOXA_API_BASE_URL) is not configured.") {
        self.reason = reason
    }

    public func exchange(_ proof: AppleIdentityProof) async throws -> AuthSession {
        throw AuthenticationServiceError.notConfigured(reason)
    }

    public func refresh(_ session: AuthSession) async throws -> AuthSession {
        throw AuthenticationServiceError.notConfigured(reason)
    }

    public func invalidate(_ session: AuthSession) async throws {
        throw AuthenticationServiceError.notConfigured(reason)
    }
}
