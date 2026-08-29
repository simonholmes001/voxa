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
    /// The backend exchange client has not been wired yet.
    case unavailable
}

/// Default service used until the backend client is injected. Every call
/// fails with `.unavailable`, so the sign-in UI renders but cannot complete
/// until the backend implementation from #17 is provided.
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
