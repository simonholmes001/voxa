import Foundation
import Observation
import os

/// Orchestrates the Sign in with Apple session lifecycle: restore on launch,
/// sign in, token refresh, and sign out. All backend interaction goes through
/// an injected `AuthenticationService`, and tokens are persisted through an
/// injected `SessionStore`.
@MainActor
@Observable
public final class AuthViewModel {
    private static let logger = Logger(subsystem: "com.simonholmes.voxa", category: "authentication")

    public private(set) var state: AuthState = .signedOut

    private let store: any SessionStore
    private let service: any AuthenticationService
    private let now: () -> Date

    public init(
        store: any SessionStore = KeychainSessionStore(),
        service: any AuthenticationService = UnavailableAuthenticationService(),
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.service = service
        self.now = now
    }

    /// Restores a persisted session on launch, refreshing it if it has expired.
    public func restore() async {
        do {
            guard let stored = try store.load() else {
                state = .signedOut
                return
            }
            if stored.isExpired(asOf: now()) {
                guard !stored.isRefreshExpired(asOf: now()) else {
                    // Refresh token is dead too — force a fresh sign in.
                    try? store.clear()
                    state = .signedOut
                    return
                }
                try await refresh(stored)
            } else {
                state = .signedIn(stored)
            }
        } catch {
            try? store.clear()
            state = .signedOut
        }
    }

    /// Exchanges an Apple identity proof for a session and persists it.
    public func signIn(with proof: AppleIdentityProof) async {
        state = .authenticating
        do {
            let session = try await service.exchange(proof)
            try store.save(session)
            state = .signedIn(session)
        } catch {
            Self.logger.error("Sign-in failed error=\(String(describing: error), privacy: .public)")
            state = .failed(Self.message(for: error))
        }
    }

    /// Signs out: invalidates the backend session (best effort) and clears the
    /// locally stored tokens.
    public func signOut() async {
        if let session = state.session {
            try? await service.invalidate(session)
        }
        try? store.clear()
        state = .signedOut
    }

    private func refresh(_ session: AuthSession) async throws {
        let refreshed = try await service.refresh(session)
        try store.save(refreshed)
        state = .signedIn(refreshed)
    }

    private static func message(for error: Error) -> String {
        switch error {
        case AuthenticationServiceError.unavailable:
            return "Sign in is not available yet. Please try again later."
        case AuthenticationServiceError.notConfigured:
            return "Sign in is not configured for this build. Please contact support."
        case AuthenticationServiceError.invalidAppleIdentity:
            return "We couldn't verify your Apple ID. Please try again."
        case AuthenticationServiceError.sessionExpired:
            return "Your session expired. Please sign in again."
        case AuthenticationServiceError.transport:
            return "We couldn't reach Voxa. Check your connection and try again."
        default:
            return "Sign in failed. Please try again."
        }
    }
}
